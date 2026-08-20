module github.com/alibaba/kubeskoop/cmd/controller

go 1.25.0

require (
	github.com/alibaba/kubeskoop v0.0.0
	github.com/alibaba/kubeskoop/pkg/controller v0.0.0
)

replace (
	github.com/alibaba/kubeskoop => ../..
	github.com/alibaba/kubeskoop/pkg/controller => ../../pkg/controller
)
