# File service icons

Replaced generic document glyphs with original-color Google Docs, Google Sheets,
Google Slides and Visual Studio Code assets. One filename classifier and one icon
view are shared by the file library, attachment picker/preview, composer chips,
message attachments, document cards and editor title.

Text, Markdown, PDF, unknown extensions and extensionless names use Docs.
Spreadsheet, presentation and source-code extensions select their respective
logos, ignoring extension case and trailing whitespace. This is demo UI only;
file storage and editing behavior are unchanged.

Validation:

- `./script/build_and_run.sh --design` succeeded without warnings or errors.
- Seven filename classification checks passed.
- `types-light.png` and `types-dark.png` render the production `MacTeamFileIcon`
  with the built asset catalog; these are component proofs, not app screenshots.
- `files-library.jpg` is the running app, with Google Docs icons on existing files.

Official asset sources:

- [Google Docs](https://www.gstatic.com/images/branding/product/2x/docs_2020q4_48dp.png)
- [Google Sheets](https://www.gstatic.com/images/branding/product/2x/sheets_2020q4_48dp.png)
- [Google Slides](https://www.gstatic.com/images/branding/product/2x/slides_2020q4_48dp.png)
- [Visual Studio Code stable icon](https://code.visualstudio.com/assets/branding/code-stable.png),
  linked from the [VS Code brand page](https://code.visualstudio.com/brand).
