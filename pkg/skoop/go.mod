module github.com/alibaba/kubeskoop/pkg/skoop

go 1.25.0

require (
	github.com/alibaba/kubeskoop v0.0.0
	github.com/alibabacloud-go/darabonba-openapi v0.2.1
	github.com/alibabacloud-go/darabonba-openapi/v2 v2.0.2
	github.com/alibabacloud-go/ecs-20140526/v2 v2.1.3
	github.com/alibabacloud-go/slb-20140515/v4 v4.0.2
	github.com/alibabacloud-go/tea v1.1.20
	github.com/alibabacloud-go/vpc-20160428/v2 v2.0.15
	github.com/bastjan/netstat v1.0.0
	github.com/beevik/etree v1.1.0
	github.com/gorilla/mux v1.8.1
	github.com/moby/ipvs v1.1.0
	github.com/moby/moby/client v0.5.0
	github.com/pkg/errors v0.9.1
	github.com/projectcalico/api v0.0.0-20220722155641-439a754a988b
	github.com/samber/lo v1.37.0
	github.com/sirupsen/logrus v1.9.3
	github.com/spf13/cobra v1.8.1
	github.com/spf13/pflag v1.0.5
	github.com/stretchr/testify v1.11.1
	github.com/vishvananda/netlink v1.3.2-0.20260404173425-c822ed716ea1
	github.com/vishvananda/netns v0.0.5
	golang.org/x/exp v0.0.0-20230515195305-f3d0a9c9a5cc
	golang.org/x/sys v0.47.0
	google.golang.org/grpc v1.82.1
	k8s.io/api v0.31.14
	k8s.io/apimachinery v0.31.14
	k8s.io/client-go v0.31.14
	k8s.io/component-base v0.31.14
	k8s.io/cri-api v0.31.14
	k8s.io/klog/v2 v2.130.1
	k8s.io/utils v0.0.0-20240711033017-18e509b52bc8
	oss.terrastruct.com/d2 v0.5.1
)

replace github.com/alibaba/kubeskoop => ../..

exclude google.golang.org/genproto v0.0.0-20210402141018-6c239bbf2bb1
exclude google.golang.org/genproto v0.0.0-20210319143718-93e7006c17a6
