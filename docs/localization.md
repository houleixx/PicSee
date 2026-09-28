# PicSee localization

Language is selected in Settings → Display → Language. The default follows the
system preference order; explicit choices are Simplified Chinese and English.
Unsupported system languages fall back to English. Choices are stored under
`PicSee.Language` and shared with other PicSee processes through the existing
preference notification mechanism.

`L10n.text` resolves a language bundle explicitly on each lookup; it does not
change `AppleLanguages`, swizzle Foundation, or require a process restart.
Resources live in `Sources/PicSee/Resources/{zh-Hans,en}.lproj/Localizable.strings`.
The bundle loader supports both SwiftPM and the packaged app; SwiftPM lowercases
locale directory names. App metadata and the Finder automation permission reason
are localized separately in `Resources/*/InfoPlist.strings`.

SwiftUI views observe `LanguageSettings`. Only cached picker/button labels get a
language-dependent identity: the viewer, screenshot canvas, document, and settings
pages retain their identities and state. Native controls use
`LanguageSettings.bind` to refresh labels in place. The subscription belongs to
the control and captures its owner weakly. Stored failures keep enough information
to render again in the new language. User filenames, annotation contents, format
identifiers, and preference values are never translated.

Use numbered `%1$@`, `%2$@` placeholders for variable content. Substitution happens
once and treats arguments as literal strings, including filenames containing `%`.
English count messages use neutral labels, avoiding incorrect singular/plural
forms. Add every key to both catalogs and use `L10n.text` at the display boundary.
Do not cache translated labels in static stored properties.

Validation:

```sh
python3 Scripts/check-localizations.py
swift test
PICSEE_SKIP_LOCAL_INSTALL=1 bash Scripts/build-app.sh
```

The audit checks Chinese source literals, catalog parity, untranslated English
values, duplicates, and interpolation placeholders. Unit tests cover fallback,
explicit language selection, persistence, and escaping. Native integration tests
switch languages in place and check menu/dialog labels, form selections, export
options, image transforms, and screenshot state. The release workflow runs the
catalog audit.

macOS owns the file chooser's navigation, standard color panel controls, Live Text
system actions, and permission dialogs. These follow macOS's application/system
language settings. PicSee updates the titles, save action, filename label, and
accessory controls that the public APIs let it own. No private system UI is patched.
