# MMDWorkbench

MMDWorkbench vendors the browser bundle from `mathpix-markdown-it`
version 3.0.1 so historical `.mmd` exports render locally without a network
connection.

- Source: <https://github.com/Mathpix/mathpix-markdown-it>
- npm package: `mathpix-markdown-it@3.0.1`
- Bundled file: `mathpix-markdown-it.js`
- SHA-256: `d8455364908573fd75b3ac80611fe3bff415614a7addefd49ec9b2fad86a5181`
- License: MIT; see `mathpix-markdown-it.LICENSE.txt`

The shared SwiftUI reader treats Mathpix Markdown as a document payload. The bundled
JavaScript is only a presentation adapter hosted by WebKit's native SwiftUI
`WebView`; it does not become part of the ATLAS intermediate representation.

## VS Code comparison

Mathpix's VS Code extension extends VS Code's Markdown preview; it is not a
Mathpix package reader. Open the exported folder (the folder containing both
the `.mmd` file and `images/`) as the VS Code workspace, open the `.mmd`, then
run **Markdown: Open Preview to the Side**. Opening only the source file gives
the preview less reliable context for resolving `./images/...` resources.

The IEEE 771 export currently contains both ordinary Markdown images and LaTeX
`\includegraphics` images. If ordinary images appear but `\includegraphics`
images do not, that is an extension integration limitation rather than a
missing image package. MMDWorkbench deliberately resolves both forms through a
package-scoped resource handler.

On iPadOS, select the enclosing Mathpix export folder when the document has an
`images/` directory. Selecting only the `.mmd` can grant the app access to that
single file while withholding its siblings. The resource handler coordinates
reads with File Provider and waits for iCloud placeholders to download.


## License

MMDWorkbench's Swift source is available under the [MIT License](LICENSE).
The bundled renderer and its dependencies retain their own licenses. See
[Mathpix's license](Sources/MMDWorkbench/Resources/mathpix-markdown-it.LICENSE.txt)
and the [bundled dependency notices](Sources/MMDWorkbench/Resources/mathpix-markdown-it.THIRD-PARTY-NOTICES.txt).
