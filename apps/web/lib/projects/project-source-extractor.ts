import pdfParse from 'pdf-parse/lib/pdf-parse.js';

export interface ExtractedProjectSource {
  contentType: string;
  file: File;
  name: string;
  size: number;
  text: string;
}

export class ProjectSourceValidationError extends Error {}

export class ProjectSourceExtractor {
  private readonly maxFileSize = 5 * 1024 * 1024;
  private readonly maxTextLength = 200_000;
  private readonly contentTypes = new Map<string, string>([
    ['.c', 'text/x-c'],
    ['.cpp', 'text/x-c++'],
    ['.cs', 'text/x-csharp'],
    ['.css', 'text/css'],
    ['.csv', 'text/csv'],
    ['.go', 'text/x-go'],
    ['.h', 'text/x-c'],
    ['.hpp', 'text/x-c++'],
    ['.html', 'text/html'],
    ['.java', 'text/x-java'],
    ['.js', 'text/javascript'],
    ['.json', 'application/json'],
    ['.jsx', 'text/jsx'],
    ['.kt', 'text/x-kotlin'],
    ['.kts', 'text/x-kotlin'],
    ['.md', 'text/markdown'],
    ['.markdown', 'text/markdown'],
    ['.pdf', 'application/pdf'],
    ['.php', 'text/x-php'],
    ['.py', 'text/x-python'],
    ['.rb', 'text/x-ruby'],
    ['.rs', 'text/x-rust'],
    ['.scss', 'text/x-scss'],
    ['.sh', 'text/x-shellscript'],
    ['.sql', 'application/sql'],
    ['.swift', 'text/x-swift'],
    ['.ts', 'text/typescript'],
    ['.tsx', 'text/tsx'],
    ['.txt', 'text/plain'],
    ['.xml', 'application/xml'],
    ['.yaml', 'application/yaml'],
    ['.yml', 'application/yaml'],
  ]);

  async extract(file: File): Promise<ExtractedProjectSource> {
    if (file.size <= 0) {
      throw new ProjectSourceValidationError('The selected file is empty');
    }
    if (file.size > this.maxFileSize) {
      throw new ProjectSourceValidationError('Files must be 5 MB or smaller');
    }
    const name = file.name.trim().slice(0, 255);
    const extension = this.extension(name);
    const contentType = this.contentTypes.get(extension);
    if (!contentType) {
      throw new ProjectSourceValidationError('This file type is not supported');
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    const text =
      extension === '.pdf'
        ? await this.extractPdf(bytes)
        : this.extractText(bytes);
    const normalizedText = text.trim().slice(0, this.maxTextLength);
    if (!normalizedText) {
      throw new ProjectSourceValidationError(
        'No readable text was found in this file',
      );
    }
    return {
      contentType,
      file: new File([bytes], name, { type: contentType }),
      name,
      size: file.size,
      text: normalizedText,
    };
  }

  private extension(name: string): string {
    const index = name.lastIndexOf('.');
    return index >= 0 ? name.slice(index).toLowerCase() : '';
  }

  private async extractPdf(bytes: Uint8Array): Promise<string> {
    try {
      const result = await pdfParse(Buffer.from(bytes));
      return result.text;
    } catch {
      throw new ProjectSourceValidationError('The PDF could not be read');
    }
  }

  private extractText(bytes: Uint8Array): string {
    try {
      const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      if (text.includes('\u0000')) {
        throw new ProjectSourceValidationError(
          'The file does not contain readable UTF-8 text',
        );
      }
      return text;
    } catch (error) {
      if (error instanceof ProjectSourceValidationError) {
        throw error;
      }
      throw new ProjectSourceValidationError(
        'The file does not contain readable UTF-8 text',
      );
    }
  }
}
