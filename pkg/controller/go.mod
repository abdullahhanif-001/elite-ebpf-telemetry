module github.com/alibaba/kubeskoop/pkg/controller

go 1.25.7

require (
	github.com/alibaba/kubeskoop v0.0.0
	github.com/alibaba/kubeskoop/pkg/skoop v0.0.0
)

replace (
	github.com/alibaba/kubeskoop => ../..
	github.com/alibaba/kubeskoop/pkg/skoop => ../skoop
)

exclude google.golang.org/genproto v0.0.0-20210402141018-6c239bbf2bb1
