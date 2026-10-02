apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${control_plane_ip}
  bindPort: 6443
nodeRegistration:
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: ${control_plane_ip}
  taints:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: ${cluster_name}
kubernetesVersion: v${kubernetes_version}
controlPlaneEndpoint: ${control_plane_ip}:6443
networking:
  podSubnet: ${pod_cidr}
  serviceSubnet: ${service_cidr}
apiServer:
  certSANs:
%{ for san in api_sans ~}
    - ${san}
%{ endfor ~}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
