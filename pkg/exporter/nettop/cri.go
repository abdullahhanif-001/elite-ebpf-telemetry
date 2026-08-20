package nettop

import (
	"context"
	"fmt"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"

	"github.com/pkg/errors"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	internalapi "k8s.io/cri-api/pkg/apis"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

var (
	criClient       internalapi.RuntimeService
	criInfo         *CRIInfo
	apiserverClient *PodCache
)

const (
	unixProtocol   = "unix"
	maxMsgSize     = 1024 * 1024 * 16
	kubeAPIVersion = "0.1.0"
)

var runtimeEndpoints = []string{"/var/run/dockershim.sock", "/run/containerd/containerd.sock", "/run/k3s/containerd/containerd.sock", "/var/run/cri-dockerd.sock"}

func initCriClient(eps []string) (err error) {
	if criClient != nil {
		return
	}

	if sock, ok := os.LookupEnv("RUNTIME_SOCK"); ok {
		if _, err = os.Stat(sock); os.IsNotExist(err) {
			return fmt.Errorf("cannot find cri sock %s", sock)
		}
		criClient, err = NewRemoteRuntimeService(sock, 10*time.Second)
		if err != nil {
			return fmt.Errorf("connect cri sock %s error: %w", sock, err)
		}
		return
	}

	for _, candidate := range eps {
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			continue
		}
		criClient, err = NewRemoteRuntimeService(candidate, 10*time.Second)
		if err != nil {
			continue
		}
		return
	}

	return fmt.Errorf("cannot find valid cri sock in %s", strings.Join(eps, ","))
}

func initCriInfo() error {
	if criInfo != nil {
		return nil
	}

	version, err := criClient.Version(context.Background(), kubeAPIVersion)
	if err != nil {
		return fmt.Errorf("failed get runtime version: %w", err)
	}
	criInfo = &CRIInfo{
		Version:        version.RuntimeApiVersion,
		RuntimeName:    version.RuntimeName,
		RuntimeVersion: version.RuntimeVersion,
	}
	log.Infof("cri info: version=%s runtime=%s runtimeVersion=%s", criInfo.Version, criInfo.RuntimeName, criInfo.RuntimeVersion)
	return nil
}

// remoteRuntimeService is a gRPC implementation of internalapi.RuntimeService (CRI v1 only).
type remoteRuntimeService struct {
	timeout       time.Duration
	runtimeClient runtimeapi.RuntimeServiceClient
}

func (r *remoteRuntimeService) Version(ctx context.Context, apiVersion string) (*runtimeapi.VersionResponse, error) {
	typedVersion, err := r.runtimeClient.Version(ctx, &runtimeapi.VersionRequest{
		Version: apiVersion,
	})
	if err != nil {
		return nil, err
	}

	if typedVersion.Version == "" || typedVersion.RuntimeName == "" || typedVersion.RuntimeApiVersion == "" || typedVersion.RuntimeVersion == "" {
		return nil, fmt.Errorf("not all fields are set in VersionResponse (%q)", *typedVersion)
	}

	return typedVersion, err
}

func getConnection(ctx context.Context, endPoint string) (*grpc.ClientConn, error) {
	addr, dialer, err := GetAddressAndDialer(endPoint)
	if err != nil {
		return nil, err
	}
	conn, err := grpc.DialContext(ctx, addr, grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock(), grpc.WithContextDialer(dialer), grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(maxMsgSize)))
	if err != nil {
		return nil, fmt.Errorf("connect endpoint '%s', make sure you are running as root and the endpoint has been started", endPoint)

	}
	return conn, nil
}

func NewRemoteRuntimeService(endpoint string, connectionTimeout time.Duration) (internalapi.RuntimeService, error) {
	ctx, cancel := context.WithTimeout(context.Background(), connectionTimeout)
	defer cancel()

	conn, err := getConnection(ctx, endpoint)
	if err != nil {
		return nil, err
	}

	service := &remoteRuntimeService{
		timeout:       connectionTimeout,
		runtimeClient: runtimeapi.NewRuntimeServiceClient(conn),
	}

	if _, err := service.runtimeClient.Version(ctx, &runtimeapi.VersionRequest{}); err != nil {
		return nil, fmt.Errorf("CRI v1 Version RPC failed (v1alpha2 is no longer supported): %w", err)
	}
	log.Warn("Using CRI v1 runtime API")

	return service, nil
}

func (r *remoteRuntimeService) Attach(_ context.Context, _ *runtimeapi.AttachRequest) (*runtimeapi.AttachResponse, error) {
	return nil, nil
}

func (r *remoteRuntimeService) CheckpointContainer(_ context.Context, _ *runtimeapi.CheckpointContainerRequest) error {
	return nil
}

func (r *remoteRuntimeService) ContainerStats(_ context.Context, _ string) (*runtimeapi.ContainerStats, error) {
	return nil, nil
}

func (r *remoteRuntimeService) CreateContainer(_ context.Context, _ string, _ *runtimeapi.ContainerConfig, _ *runtimeapi.PodSandboxConfig) (string, error) {
	return "", nil
}

func (r *remoteRuntimeService) Exec(_ context.Context, _ *runtimeapi.ExecRequest) (*runtimeapi.ExecResponse, error) {
	return nil, nil
}

func (r *remoteRuntimeService) ExecSync(_ context.Context, _ string, _ []string, _ time.Duration) (stdout []byte, stderr []byte, err error) {
	return nil, nil, nil
}

func (r *remoteRuntimeService) GetContainerEvents(_ context.Context, _ chan *runtimeapi.ContainerEventResponse, _ func(runtimeapi.RuntimeService_GetContainerEventsClient)) error {
	return nil
}

func (r *remoteRuntimeService) PortForward(_ context.Context, _ *runtimeapi.PortForwardRequest) (*runtimeapi.PortForwardResponse, error) {
	return nil, nil
}

func (r *remoteRuntimeService) RemoveContainer(_ context.Context, _ string) (err error) {
	return nil
}

func (r *remoteRuntimeService) RemovePodSandbox(_ context.Context, _ string) (err error) {
	return nil
}

func (r *remoteRuntimeService) ReopenContainerLog(_ context.Context, _ string) (err error) {
	return nil
}

func (r *remoteRuntimeService) RunPodSandbox(_ context.Context, _ *runtimeapi.PodSandboxConfig, _ string) (string, error) {
	return "", nil
}

func (r *remoteRuntimeService) StartContainer(_ context.Context, _ string) (err error) {
	return nil
}

func (r *remoteRuntimeService) StopContainer(_ context.Context, _ string, _ int64) (err error) {
	return nil
}

func (r *remoteRuntimeService) StopPodSandbox(_ context.Context, _ string) (err error) {
	return nil
}

func (r *remoteRuntimeService) UpdateContainerResources(_ context.Context, _ string, _ *runtimeapi.ContainerResources) (err error) {
	return nil
}

func (r *remoteRuntimeService) UpdateRuntimeConfig(_ context.Context, _ *runtimeapi.RuntimeConfig) (err error) {
	return nil
}

func (r *remoteRuntimeService) RuntimeConfig(_ context.Context) (*runtimeapi.RuntimeConfigResponse, error) {
	return &runtimeapi.RuntimeConfigResponse{}, nil
}

func (r *remoteRuntimeService) ListMetricDescriptors(_ context.Context) ([]*runtimeapi.MetricDescriptor, error) {
	return nil, nil
}

func (r *remoteRuntimeService) ListPodSandboxMetrics(_ context.Context) ([]*runtimeapi.PodSandboxMetrics, error) {
	return nil, nil
}

func (r *remoteRuntimeService) Status(ctx context.Context, verbose bool) (*runtimeapi.StatusResponse, error) {
	resp, err := r.runtimeClient.Status(ctx, &runtimeapi.StatusRequest{
		Verbose: verbose,
	})
	if err != nil {
		return nil, err
	}

	if resp.Status == nil || len(resp.Status.Conditions) < 2 {
		return nil, errors.New("RuntimeReady or NetworkReady condition are not set")
	}

	return resp, nil
}

func (r *remoteRuntimeService) PodSandboxStatus(ctx context.Context, podSandBoxID string, verbose bool) (*runtimeapi.PodSandboxStatusResponse, error) {
	resp, err := r.runtimeClient.PodSandboxStatus(ctx, &runtimeapi.PodSandboxStatusRequest{
		PodSandboxId: podSandBoxID,
		Verbose:      verbose,
	})
	if err != nil {
		return nil, err
	}

	if resp.Status != nil {
		if err := verifySandboxStatus(resp.Status); err != nil {
			return nil, err
		}
	}

	return resp, nil
}

func (r *remoteRuntimeService) PodSandboxStats(ctx context.Context, podSandboxID string) (*runtimeapi.PodSandboxStats, error) {
	resp, err := r.runtimeClient.PodSandboxStats(ctx, &runtimeapi.PodSandboxStatsRequest{
		PodSandboxId: podSandboxID,
	})
	if err != nil {
		return nil, err
	}

	return resp.GetStats(), nil
}

func (r *remoteRuntimeService) ListPodSandboxStats(ctx context.Context, filter *runtimeapi.PodSandboxStatsFilter) ([]*runtimeapi.PodSandboxStats, error) {
	resp, err := r.runtimeClient.ListPodSandboxStats(ctx, &runtimeapi.ListPodSandboxStatsRequest{
		Filter: filter,
	})
	if err != nil {
		return nil, err
	}

	return resp.GetStats(), nil
}

func (r *remoteRuntimeService) ListPodSandbox(ctx context.Context, filter *runtimeapi.PodSandboxFilter) ([]*runtimeapi.PodSandbox, error) {
	resp, err := r.runtimeClient.ListPodSandbox(ctx, &runtimeapi.ListPodSandboxRequest{
		Filter: filter,
	})
	if err != nil {
		return nil, err
	}

	return resp.Items, nil
}

func (r *remoteRuntimeService) ListContainers(ctx context.Context, filter *runtimeapi.ContainerFilter) ([]*runtimeapi.Container, error) {
	resp, err := r.runtimeClient.ListContainers(ctx, &runtimeapi.ListContainersRequest{
		Filter: filter,
	})
	if err != nil {
		return nil, err
	}

	return resp.Containers, nil
}

func (r *remoteRuntimeService) ListContainerStats(ctx context.Context, filter *runtimeapi.ContainerStatsFilter) ([]*runtimeapi.ContainerStats, error) {
	resp, err := r.runtimeClient.ListContainerStats(ctx, &runtimeapi.ListContainerStatsRequest{
		Filter: filter,
	})
	if err != nil {
		return nil, err
	}

	return resp.GetStats(), nil
}

func (r *remoteRuntimeService) ContainerStatus(ctx context.Context, containerID string, verbose bool) (*runtimeapi.ContainerStatusResponse, error) {
	resp, err := r.runtimeClient.ContainerStatus(ctx, &runtimeapi.ContainerStatusRequest{
		ContainerId: containerID,
		Verbose:     verbose,
	})
	if err != nil {
		return nil, err
	}

	if resp.Status != nil {
		if err := verifyContainerStatus(resp.Status); err != nil {
			return nil, err
		}
	}

	return resp, nil
}

func parseEndpoint(endpoint string) (string, string, error) {
	u, err := url.Parse(endpoint)
	if err != nil {
		return "", "", err
	}

	switch u.Scheme {
	case "tcp":
		return "tcp", u.Host, nil

	case "unix":
		return "unix", u.Path, nil

	case "":
		return "", "", fmt.Errorf("using %q as endpoint is deprecated, please consider using full url format", endpoint)

	default:
		return u.Scheme, "", fmt.Errorf("protocol %q not supported", u.Scheme)
	}
}

func parseEndpointWithFallbackProtocol(endpoint string, fallbackProtocol string) (protocol string, addr string, err error) {
	if protocol, addr, err = parseEndpoint(endpoint); err != nil && protocol == "" {
		fallbackEndpoint := fallbackProtocol + "://" + endpoint
		protocol, addr, err = parseEndpoint(fallbackEndpoint)
	}
	return
}

// GetAddressAndDialer returns the address parsed from the given endpoint and a context dialer.
func GetAddressAndDialer(endpoint string) (string, func(ctx context.Context, addr string) (net.Conn, error), error) {
	protocol, addr, err := parseEndpointWithFallbackProtocol(endpoint, unixProtocol)
	if err != nil {
		return "", nil, err
	}
	if protocol != unixProtocol {
		return "", nil, fmt.Errorf("only support unix socket endpoint")
	}

	return addr, dial, nil
}

func dial(ctx context.Context, addr string) (net.Conn, error) {
	return (&net.Dialer{}).DialContext(ctx, unixProtocol, addr)
}
