//go:build !darwin

package main

import "errors"

func swapPaths(a, b string) error { return errors.New("not supported") }
