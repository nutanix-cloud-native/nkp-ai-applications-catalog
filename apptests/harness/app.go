// Copyright 2025 Nutanix. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

package harness

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/nutanix-cloud-native/nkp-catalog-tests/environment"
)

// appScenario installs a catalog app from applications/<name>/<version>/helmrelease/.
type appScenario struct {
	name    string
	version string
}

func newAppScenario(name, version string) *appScenario {
	return &appScenario{name: name, version: version}
}

func (a *appScenario) Install(ctx context.Context, env *environment.Env) error {
	appPath, err := a.versionPath()
	if err != nil {
		return err
	}
	return a.install(ctx, env, appPath)
}

func (a *appScenario) Upgrade(ctx context.Context, env *environment.Env) error {
	return a.Install(ctx, env)
}

func (a *appScenario) install(ctx context.Context, env *environment.Env, appPath string) error {
	return env.ApplyKustomizations(ctx, filepath.Join(appPath, "helmrelease"), map[string]string{
		"releaseNamespace":   defaultNamespace,
		"releaseName":        a.name,
		"workspaceNamespace": defaultNamespace,
		"appVersion":         filepath.Base(appPath),
	})
}

func (a *appScenario) versionPath() (string, error) {
	dir, err := appDir(a.name)
	if err != nil {
		return "", err
	}
	if a.version == "" {
		versions, err := appVersionDirs(a.name)
		if err != nil {
			return "", err
		}
		if len(versions) == 0 {
			return "", fmt.Errorf("no application directory found for %s in %s", a.name, dir)
		}
		return filepath.Join(dir, versions[len(versions)-1]), nil
	}
	path := filepath.Join(dir, a.version)
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("no application directory found for app: %s of version: %s", a.name, a.version)
	}
	return path, nil
}
