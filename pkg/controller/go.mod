module github.com/alibaba/kubeskoop/pkg/controller

go 1.25.0

require (
	github.com/alibaba/kubeskoop v0.0.0
	github.com/alibaba/kubeskoop/pkg/skoop v0.0.0
)

replace (
	github.com/alibaba/kubeskoop => ../..
	github.com/alibaba/kubeskoop/pkg/skoop => ../skoop
)
