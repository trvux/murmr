package main

import (
	"os"
	"strings"
	"sync/atomic"
)

// The engine words a few notices that the macOS app shows (an error, "the backup service answered"). The app tells it
// the language of its interface: MURMR_LANG at start ("vi" or "en"), and a "lang <vi|en>" line on stdin when the person
// switches. Run on its own, the engine words them in Vietnamese, as it always did.
var uiEnglish atomic.Bool

func init() { SetUILang(os.Getenv("MURMR_LANG")) }

// SetUILang takes "en" for English; anything else means Vietnamese.
func SetUILang(lang string) { uiEnglish.Store(strings.EqualFold(strings.TrimSpace(lang), "en")) }

// ui picks the wording for the current interface language.
func ui(vi, en string) string {
	if uiEnglish.Load() {
		return en
	}
	return vi
}
