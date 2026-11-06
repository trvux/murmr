package main

import (
	"os"
	"testing"
)

func TestStyleFor(t *testing.T) {
	t.Setenv("HOME", t.TempDir()) // no user apps.txt
	cases := []struct {
		c    appCtx
		want string
	}{
		{appCtx{"com.mitchellh.ghostty", "~/code"}, styleCasual},
		{appCtx{"com.google.Chrome", "Claude"}, styleCasual},
		{appCtx{"com.google.Chrome", "Inbox (3) - me@gmail.com - Gmail"}, styleNeutral},
		{appCtx{"net.imput.helium", "Inbox - Gmail"}, styleNeutral},
		{appCtx{"com.vng.zalo", ""}, styleNeutral},
		{appCtx{"", ""}, styleNeutral},
	}
	for _, c := range cases {
		if got := styleFor(c.c); got != c.want {
			t.Errorf("%+v: got %s, want %s", c.c, got, c.want)
		}
	}
}

func TestStyleForUserRules(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	dir := home + "/.config/murmr"
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	rules := "com.vng.zalo casual\ntitle:Team Chat neutral\nbogus line\n"
	if err := os.WriteFile(dir+"/apps.txt", []byte(rules), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := styleFor(appCtx{"com.vng.zalo", ""}); got != styleCasual {
		t.Errorf("bundle rule: got %s", got)
	}
	if got := styleFor(appCtx{"com.google.Chrome", "My Team Chat | Slack"}); got != styleNeutral {
		t.Errorf("title rule with a space: got %s", got)
	}
}
