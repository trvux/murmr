package main

import "testing"

func TestUIWording(t *testing.T) {
	defer SetUILang("")
	SetUILang("")
	if got := ui("xin chào", "hello"); got != "xin chào" {
		t.Errorf("default is Vietnamese, got %q", got)
	}
	SetUILang("en")
	if got := ui("xin chào", "hello"); got != "hello" {
		t.Errorf("en: got %q", got)
	}
	SetUILang(" EN ")
	if got := ui("xin chào", "hello"); got != "hello" {
		t.Errorf("spaces and case are ignored, got %q", got)
	}
	SetUILang("fr")
	if got := ui("xin chào", "hello"); got != "xin chào" {
		t.Errorf("an unknown language means Vietnamese, got %q", got)
	}
}
