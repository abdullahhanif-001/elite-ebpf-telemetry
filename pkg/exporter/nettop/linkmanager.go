package nettop

import (
	"sync"
	"syscall"

	log "github.com/sirupsen/logrus"
	"github.com/vishvananda/netlink"
)

// LinkInfo is a snapshot of a network interface.
type LinkInfo struct {
	Index int
	Name  string
	Link  netlink.Link
}

// LinkEventType distinguishes add from delete events.
type LinkEventType int

const (
	LinkAdded LinkEventType = iota
	LinkDeleted
)

// LinkEvent represents a single link change.
type LinkEvent struct {
	Type LinkEventType
	Info LinkInfo
}

// LinkListener receives notifications on interface changes.
type LinkListener interface {
	OnLinkAdd(info LinkInfo)
	OnLinkDel(info LinkInfo)
}

// listenerEntry holds a registered listener with its dedicated event channel.
type listenerEntry struct {
	listener LinkListener
	ch       chan LinkEvent
	done     chan struct{}
}

type linkManager struct {
	links   map[int]LinkInfo // ifIndex -> LinkInfo
	entries []*listenerEntry
	mu      sync.RWMutex
	done    chan struct{}
}

var defaultLinkManager *linkManager

// StartLinkManager initialises the global link manager: populates the
// initial link cache and starts a netlink subscription for changes.
func StartLinkManager() error {
	m := &linkManager{
		links: make(map[int]LinkInfo),
		done:  make(chan struct{}),
	}

	links, err := netlink.LinkList()
	if err != nil {
		return err
	}
	for _, l := range links {
		m.links[l.Attrs().Index] = LinkInfo{
			Index: l.Attrs().Index,
			Name:  l.Attrs().Name,
			Link:  l,
		}
	}

	ch := make(chan netlink.LinkUpdate)
	if err := netlink.LinkSubscribe(ch, m.done); err != nil {
		return err
	}

	go m.eventLoop(ch)

	defaultLinkManager = m
	return nil
}

// StopLinkManager shuts down the global link manager.
func StopLinkManager() {
	m := defaultLinkManager
	if m == nil {
		return
	}
	close(m.done)

	m.mu.Lock()
	for _, entry := range m.entries {
		close(entry.done)
	}
	m.entries = nil
	m.mu.Unlock()

	defaultLinkManager = nil
}

// eventLoop processes netlink link updates.
func (m *linkManager) eventLoop(ch <-chan netlink.LinkUpdate) {
	for {
		select {
		case update, ok := <-ch:
			if !ok {
				return
			}
			m.handleUpdate(update)
		case <-m.done:
			return
		}
	}
}

func (m *linkManager) handleUpdate(update netlink.LinkUpdate) {
	m.mu.Lock()
	defer m.mu.Unlock()

	index := update.Attrs().Index
	name := update.Attrs().Name

	switch update.Header.Type {
	case syscall.RTM_NEWLINK:
		info := LinkInfo{
			Index: index,
			Name:  name,
			Link:  update.Link,
		}
		m.links[index] = info
		m.broadcast(LinkEvent{Type: LinkAdded, Info: info})

	case syscall.RTM_DELLINK:
		info, ok := m.links[index]
		if !ok {
			info = LinkInfo{Index: index, Name: name}
		}
		delete(m.links, index)
		m.broadcast(LinkEvent{Type: LinkDeleted, Info: info})
	}
}

// broadcast sends an event to every registered listener channel.
// Must be called with m.mu held (write lock).
func (m *linkManager) broadcast(ev LinkEvent) {
	for _, entry := range m.entries {
		select {
		case entry.ch <- ev:
		default:
			log.Warnf("linkmanager: event channel full for listener, dropping event")
		}
	}
}

// RegisterLinkListener adds a listener and replays all existing links as
// LinkAdded events. Replay events and future netlink events are both
// delivered through the listener's dedicated channel, ensuring strict
// ordering and no event loss.
func RegisterLinkListener(l LinkListener) {
	m := defaultLinkManager
	if m == nil {
		log.Warnf("linkmanager: RegisterLinkListener called before StartLinkManager")
		return
	}
	m.registerListener(l)
}

func (m *linkManager) registerListener(l LinkListener) {
	m.mu.Lock()

	entry := &listenerEntry{
		listener: l,
		ch:       make(chan LinkEvent, len(m.links)+1024),
		done:     make(chan struct{}),
	}

	// Enqueue replay events for all existing links while holding lock,
	// so no netlink event can slip between snapshot and subscribe.
	for _, info := range m.links {
		entry.ch <- LinkEvent{Type: LinkAdded, Info: info}
	}

	m.entries = append(m.entries, entry)
	m.mu.Unlock()

	// Start dispatch goroutine for this listener.
	go func() {
		for {
			select {
			case ev := <-entry.ch:
				switch ev.Type {
				case LinkAdded:
					l.OnLinkAdd(ev.Info)
				case LinkDeleted:
					l.OnLinkDel(ev.Info)
				}
			case <-entry.done:
				return
			}
		}
	}()
}

// UnregisterLinkListener removes a previously registered listener and
// stops its dispatch goroutine.
func UnregisterLinkListener(l LinkListener) {
	m := defaultLinkManager
	if m == nil {
		return
	}
	m.unregisterListener(l)
}

func (m *linkManager) unregisterListener(l LinkListener) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for i, entry := range m.entries {
		if entry.listener == l {
			close(entry.done)
			m.entries = append(m.entries[:i], m.entries[i+1:]...)
			return
		}
	}
}

// --------------- Lookup API ---------------

// GetLinkNameByIndex returns the cached interface name for the given index.
func GetLinkNameByIndex(index int) (string, bool) {
	m := defaultLinkManager
	if m == nil {
		return "", false
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	info, ok := m.links[index]
	if !ok {
		return "", false
	}
	return info.Name, true
}

// GetLinkByIndex returns the cached LinkInfo for the given index.
func GetLinkByIndex(index int) (LinkInfo, bool) {
	m := defaultLinkManager
	if m == nil {
		return LinkInfo{}, false
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	info, ok := m.links[index]
	return info, ok
}

// GetAllLinks returns a snapshot of all cached links.
func GetAllLinks() []LinkInfo {
	m := defaultLinkManager
	if m == nil {
		return nil
	}
	m.mu.RLock()
	defer m.mu.RUnlock()
	ret := make([]LinkInfo, 0, len(m.links))
	for _, info := range m.links {
		ret = append(ret, info)
	}
	return ret
}
