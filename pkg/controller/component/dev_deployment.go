package component

import (
	component "halkyon.io/api/component/v1beta1"
	"k8s.io/api/apps/v1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

//buildDevDeployment returns the Deployment config object
func (res deployment) installDev(empty bool) (runtime.Object, error) {
	dep := &appsv1.Deployment{}

	if !empty {
		c := res.ownerAsComponent()
		ls := getAppLabels(c)

		// create runtime container
		runtimeContainer, err := getBaseContainerFor(c)
		if err != nil {
			return nil, err
		}
		runtimeContainer.Args = []string{
			"-c",
			"/var/lib/supervisord/conf/supervisor.conf",
		}
		runtimeContainer.Command = []string{"/var/lib/supervisord/bin/supervisord"}
		runtimeContainer.Ports = []corev1.ContainerPort{{
			ContainerPort: c.Spec.Port,
			Name:          "http",
			Protocol:      "TCP",
		}}
		runtimeContainer.VolumeMounts = append(runtimeContainer.VolumeMounts, corev1.VolumeMount{Name: c.Spec.Storage.Name, MountPath: "/deployments"})
		runtimeContainer.VolumeMounts = append(runtimeContainer.VolumeMounts, corev1.VolumeMount{Name: c.Spec.Storage.Name, MountPath: "/usr/src"})
		runtimeContainer.VolumeMounts = append(runtimeContainer.VolumeMounts, corev1.VolumeMount{Name: c.Spec.Storage.Name, MountPath: "/tmp/artefacts"})

		// create the supervisor init container
		supervisorContainer, err := getBaseContainerFor(getSupervisor())
		if err != nil {
			return nil, err
		}
		supervisorContainer.TerminationMessagePath = "/dev/termination-log"
		supervisorContainer.TerminationMessagePolicy = "File"

		dep.ObjectMeta = metav1.ObjectMeta{
			Name:      res.Name(),
			Namespace: c.Namespace,
			Labels:    ls,
		}
		dep.Spec = v1.DeploymentSpec{
			Strategy: v1.DeploymentStrategy{
				Type: v1.RollingUpdateDeploymentStrategyType,
			},
			Selector: &metav1.LabelSelector{
				MatchLabels: ls,
			},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: ls,
					Name:   c.Name,
				},
				Spec: corev1.PodSpec{
					Containers:     []corev1.Container{runtimeContainer},
					InitContainers: []corev1.Container{supervisorContainer},
					Volumes: []corev1.Volume{
						{Name: "shared-data",
							VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}},
						{Name: c.Spec.Storage.Name,
							VolumeSource: corev1.VolumeSource{PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{ClaimName: c.Spec.Storage.Name}}},
					},
				}},
		}
	}

	// Set Component instance as the owner and controller
	return dep, nil
}

func getBaseContainerFor(component *component.Component) (corev1.Container, error) {
	runtimeImage, err := getImageInfo(component)
	if err != nil {
		return corev1.Container{}, err
	}

	container := corev1.Container{
		Env:             populatePodEnvVar(component),
		Image:           runtimeImage.RegistryRef,
		ImagePullPolicy: corev1.PullAlways,
		Name:            component.Name,
		VolumeMounts: []corev1.VolumeMount{
			{Name: "shared-data", MountPath: "/var/lib/supervisord"},
		},
	}
	return container, nil
}
