// Copyright 2025 Nutanix. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package harness

import (
	"context"
	"flag"
	"fmt"
	"os"
	"testing"
	"time"

	fluxhelmv2 "github.com/fluxcd/helm-controller/api/v2"
	. "github.com/onsi/ginkgo/v2"
	"github.com/onsi/gomega"
	genericClient "sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"

	"github.com/nutanix-cloud-native/nkp-catalog-tests/client"
	"github.com/nutanix-cloud-native/nkp-catalog-tests/docker"
	"github.com/nutanix-cloud-native/nkp-catalog-tests/environment"
	"github.com/nutanix-cloud-native/nkp-catalog-tests/flux"
	"github.com/nutanix-cloud-native/nkp-catalog-tests/kind"
)

const (
	defaultNamespace = "default"
	pollInterval     = 2 * time.Second
)

var (
	env       *environment.Env
	ctx       context.Context
	k8sClient genericClient.Client

	appVersion         *string
	useExistingCluster bool

	network *docker.NetworkResource
)

// InitSuite registers the -app-version flag and a Ginkgo BeforeSuite that
// initialises the cluster connection (E2E_KUBECONFIG) or Docker network
// (Kind). Call this from your suite's init() function.
func InitSuite() {
	appVersion = flag.String("app-version", "", "The version of the application (required)")

	var _ = BeforeSuite(func() {
		gomega.Expect(*appVersion).ToNot(gomega.BeEmpty(), "-app-version flag is required")

		log.SetLogger(zap.New(zap.WriteTo(GinkgoWriter), zap.UseDevMode(true)))
		ctx = context.Background()

		if kubeconfig := os.Getenv("E2E_KUBECONFIG"); kubeconfig != "" {
			useExistingCluster = true
			env = &environment.Env{}

			typedClient, err := client.NewClient(kubeconfig)
			gomega.Expect(err).ShouldNot(gomega.HaveOccurred())
			env.K8sClient = typedClient

			scheme := flux.NewScheme()
			_ = fluxhelmv2.AddToScheme(scheme)

			k8sClient, err = genericClient.New(typedClient.Config(), genericClient.Options{Scheme: scheme})
			gomega.Expect(err).ShouldNot(gomega.HaveOccurred())
		} else {
			var err error
			network, err = kind.EnsureDockerNetworkExist(ctx, "", false)
			gomega.Expect(err).ShouldNot(gomega.HaveOccurred())

			env = &environment.Env{
				Network: network,
			}
		}
	})
}

// RunSuite is the standard Ginkgo test entry point. Call this from your
// suite's TestApplications function.
func RunSuite(t *testing.T) {
	t.Helper()
	gomega.RegisterFailHandler(Fail)
	suiteConfig, reporterConfig := GinkgoConfiguration()
	RunSpecs(t, "Application Test Suite", suiteConfig, reporterConfig)
}

func setupKindCluster() error {
	if useExistingCluster {
		return nil
	}

	if ctx == nil {
		ctx = context.Background()
	}

	err := env.Provision(ctx)
	if err != nil {
		return err
	}

	scheme := flux.NewScheme()
	_ = fluxhelmv2.AddToScheme(scheme)

	k8sClient, err = genericClient.New(env.K8sClient.Config(), genericClient.Options{Scheme: scheme})
	if err != nil {
		return err
	}

	return nil
}

func waitForFluxCRDs() error {
	type gvr struct{ group, version, resource string }
	required := []gvr{
		{"helm.toolkit.fluxcd.io", "v2", "helmreleases"},
		{"source.toolkit.fluxcd.io", "v1", "ocirepositories"},
		{"kustomize.toolkit.fluxcd.io", "v1", "kustomizations"},
	}

	waitCtx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()

	for {
		allFound := true
		for _, r := range required {
			_, err := env.K8sClient.Clientset().Discovery().
				ServerResourcesForGroupVersion(r.group + "/" + r.version)
			if err != nil {
				GinkgoWriter.Printf("Waiting for API %s/%s: %v\n", r.group, r.version, err)
				allFound = false
				break
			}
		}
		if allFound {
			GinkgoWriter.Printf("All Flux CRDs are discoverable, refreshing clients\n")
			scheme := flux.NewScheme()
			_ = fluxhelmv2.AddToScheme(scheme)
			c, err := genericClient.New(env.K8sClient.Config(), genericClient.Options{Scheme: scheme})
			if err != nil {
				return fmt.Errorf("recreating client after CRD discovery: %w", err)
			}
			env.SetClient(c)
			k8sClient = c
			return nil
		}

		select {
		case <-waitCtx.Done():
			return fmt.Errorf("timed out waiting for Flux CRDs to become available")
		case <-time.After(2 * time.Second):
		}
	}
}

func teardownCluster() error {
	if useExistingCluster || os.Getenv("SKIP_CLUSTER_TEARDOWN") != "" {
		return nil
	}
	return env.Destroy(ctx)
}
