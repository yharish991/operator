package component

import (
	component "halkyon.io/api/component/v1beta1"
	framework "halkyon.io/operator-framework"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

type pvc struct {
	base
}

var _ framework.DependentResource = &pvc{}

func newPvc(owner *component.Component) pvc {
	p := pvc{base: newBaseDependent(&corev1.PersistentVolumeClaim{}, owner)}
	p.NameFn = p.Name
	return p
}

func (res pvc) Build(empty bool) (runtime.Object, error) {
	pvc := &corev1.PersistentVolumeClaim{}

	if !empty {
		c := res.ownerAsComponent()
		ls := getAppLabels(c)
		name := res.Name()
		pvc.ObjectMeta = metav1.ObjectMeta{
			Name:      name,
			Namespace: c.Namespace,
			Labels:    ls,
		}
		pvc.Spec = corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{
				getAccessMode(c),
			},
			Resources: corev1.ResourceRequirements{
				Requests: corev1.ResourceList{
					corev1.ResourceStorage: getCapacity(c),
				},
			},
		}
	}

	return pvc, nil
}

func (res pvc) Name() string {
	return PVCName(res.ownerAsComponent())
}

func getCapacity(c *component.Component) resource.Quantity {
	specified := c.Spec.Storage.Capacity
	if len(specified) == 0 {
		specified = "1Gi"
		c.Spec.Storage.Capacity = specified
	}
	return resource.MustParse(specified)
}

func getAccessMode(c *component.Component) corev1.PersistentVolumeAccessMode {
	storage := c.Spec.Storage.Mode
	mode := corev1.ReadWriteOnce
	switch storage {
	case "ReadWriteMany":
		mode = corev1.ReadWriteMany
	case "ReadOnlyMany":
		mode = corev1.ReadOnlyMany
	}
	c.Spec.Storage.Mode = string(mode)
	return mode
}
