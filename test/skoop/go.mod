module github.com/alibaba/kubeskoop/test/skoop

go 1.25.0

require github.com/alibaba/kubeskoop/pkg/skoop v0.0.0

replace github.com/alibaba/kubeskoop/pkg/skoop => ../../pkg/skoop

exclude google.golang.org/genproto v0.0.0-20210402141018-6c239bbf2bb1
exclude google.golang.org/genproto v0.0.0-20210319143718-93e7006c17a6
