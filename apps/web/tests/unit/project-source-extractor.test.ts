import assert from 'node:assert/strict';
import test from 'node:test';

import {
  ProjectSourceExtractor,
  ProjectSourceValidationError,
} from '@/lib/projects/project-source-extractor';

test('text sources are extracted and capped at 200000 characters', async () => {
  const source = await new ProjectSourceExtractor().extract(
    new File(['a'.repeat(210_000)], 'notes.txt', { type: 'text/plain' }),
  );

  assert.equal(source.text.length, 200_000);
  assert.equal(source.contentType, 'text/plain');
});

test('empty, oversized, and unsupported sources are rejected', async () => {
  const extractor = new ProjectSourceExtractor();
  await assert.rejects(
    extractor.extract(new File([], 'empty.txt')),
    ProjectSourceValidationError,
  );
  await assert.rejects(
    extractor.extract(
      new File([new Uint8Array(5 * 1024 * 1024 + 1)], 'large.txt'),
    ),
    ProjectSourceValidationError,
  );
  await assert.rejects(
    extractor.extract(new File(['hello'], 'document.docx')),
    ProjectSourceValidationError,
  );
});

test('invalid PDFs are rejected with a readable validation error', async () => {
  await assert.rejects(
    new ProjectSourceExtractor().extract(
      new File(['not a pdf'], 'broken.pdf', { type: 'application/pdf' }),
    ),
    ProjectSourceValidationError,
  );
});

test('PDF text is extracted during upload', async () => {
  const source = await new ProjectSourceExtractor().extract(
    new File([createPdf('Launch ready')], 'brief.pdf', {
      type: 'application/pdf',
    }),
  );

  assert.match(source.text, /Launch ready/);
  assert.equal(source.contentType, 'application/pdf');
});

function createPdf(text: string): string {
  const stream = `BT\n/F1 12 Tf\n72 720 Td\n(${text}) Tj\nET`;
  const objects = [
    '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
    '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
    '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n',
    '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    `5 0 obj\n<< /Length ${stream.length} >>\nstream\n${stream}\nendstream\nendobj\n`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = objects.map((object) => {
    const offset = pdf.length;
    pdf += object;
    return offset;
  });
  const xrefOffset = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  pdf += offsets
    .map((offset) => `${offset.toString().padStart(10, '0')} 00000 n \n`)
    .join('');
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return pdf;
}
