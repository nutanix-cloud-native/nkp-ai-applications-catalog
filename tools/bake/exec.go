package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Runs an external tool and returns its stdout; stderr is wrapped into the
// error. Used for tools we consume output from (kustomize build).
func capture(name string, args ...string) ([]byte, error) {
	//nolint:gosec // bake invokes fixed tools (git/kustomize/crane) with computed, non-user args
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("%s %s: %w\n%s", name, strings.Join(args, " "), err, stderr.String())
	}
	return out, nil
}

// Runs a tool, discarding its stdout but folding stderr into the error so a
// failure (bad ref, no network) is debuggable. Used for tools whose output we
// don't consume (git clone).
func quiet(name string, args ...string) error {
	//nolint:gosec // bake invokes fixed tools (git/kustomize/crane) with computed, non-user args
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s %s: %w\n%s", name, strings.Join(args, " "), err, stderr.String())
	}
	return nil
}

// Runs a tool inheriting our stdout/stderr (crane copy progress).
func stream(name string, args ...string) error {
	//nolint:gosec // bake invokes fixed tools (git/kustomize/crane) with computed, non-user args
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// Reports whether a tool is on PATH.
func have(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}
