package nettop

import (
	"fmt"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

// verifySandboxStatus verified whether all required fields are set in PodSandboxStatus.
func verifySandboxStatus(status *runtimeapi.PodSandboxStatus) error {
	if status.Id == "" {
		return fmt.Errorf("status.Id is not set")
	}

	if status.Metadata == nil {
		return fmt.Errorf("status.Metadata is not set")
	}

	metadata := status.Metadata
	if metadata.Name == "" || metadata.Namespace == "" || metadata.Uid == "" {
		return fmt.Errorf("metadata.Name, metadata.Namespace or metadata.Uid is not in metadata %q", metadata)
	}

	if status.CreatedAt == 0 {
		return fmt.Errorf("status.CreatedAt is not set")
	}

	return nil
}

// verifyContainerStatus verified whether all required fields are set in ContainerStatus.
func verifyContainerStatus(status *runtimeapi.ContainerStatus) error {
	if status.Id == "" {
		return fmt.Errorf("status.Id is not set")
	}

	if status.Metadata == nil {
		return fmt.Errorf("status.Metadata is not set")
	}

	metadata := status.Metadata
	if metadata.Name == "" {
		return fmt.Errorf("metadata.Name is not in metadata %q", metadata)
	}

	if status.CreatedAt == 0 {
		return fmt.Errorf("status.CreatedAt is not set")
	}

	if status.Image == nil || status.Image.Image == "" {
		return fmt.Errorf("status.Image is not set")
	}

	if status.ImageRef == "" {
		return fmt.Errorf("status.ImageRef is not set")
	}

	return nil
}
