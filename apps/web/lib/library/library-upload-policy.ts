const MAX_LIBRARY_UPLOAD_BYTES = 25 * 1024 * 1024;

const supportedExtensions = new Set([
  'c',
  'cpp',
  'cs',
  'csv',
  'doc',
  'docx',
  'gif',
  'go',
  'h',
  'hpp',
  'html',
  'java',
  'jpeg',
  'jpg',
  'js',
  'json',
  'jsx',
  'kt',
  'md',
  'pdf',
  'php',
  'png',
  'ppt',
  'pptx',
  'py',
  'rb',
  'rs',
  'scss',
  'sh',
  'sql',
  'swift',
  'ts',
  'tsx',
  'txt',
  'webp',
  'xls',
  'xlsx',
  'xml',
  'yaml',
  'yml',
]);

export class LibraryUploadPolicy {
  validate(file: File): void {
    this.validateMetadata(file.name, file.size);
  }

  validateMetadata(name: string, size: number): void {
    if (size <= 0) {
      throw new Error('The selected file is empty');
    }
    if (size > MAX_LIBRARY_UPLOAD_BYTES) {
      throw new Error('Files must be 25 MB or smaller');
    }
    const extension = name.split('.').at(-1)?.toLocaleLowerCase();
    if (!extension || !supportedExtensions.has(extension)) {
      throw new Error('This file type is not supported');
    }
  }
}
