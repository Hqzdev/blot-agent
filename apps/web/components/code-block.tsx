'use client';

import { ClipboardIcon } from 'lucide-react';
import React, { useState } from 'react';
import SyntaxHighlighter from 'react-syntax-highlighter';

const graphiteTheme: Record<string, React.CSSProperties> = {
  hljs: {
    background: '#f9f9f9',
    color: '#0d0d0d',
    display: 'block',
    overflowX: 'auto',
  },
  'hljs-comment': { color: '#8f8f8f' },
  'hljs-quote': { color: '#8f8f8f' },
  'hljs-keyword': { color: '#0d0d0d', fontWeight: '600' },
  'hljs-selector-tag': { color: '#0d0d0d', fontWeight: '600' },
  'hljs-subst': { color: '#0d0d0d' },
  'hljs-number': { color: '#5d5d5d' },
  'hljs-literal': { color: '#5d5d5d' },
  'hljs-variable': { color: '#5d5d5d' },
  'hljs-template-variable': { color: '#5d5d5d' },
  'hljs-string': { color: '#5d5d5d' },
  'hljs-title': { color: '#0d0d0d', fontWeight: '600' },
  'hljs-section': { color: '#0d0d0d', fontWeight: '600' },
  'hljs-type': { color: '#0d0d0d' },
  'hljs-built_in': { color: '#0d0d0d' },
  'hljs-builtin-name': { color: '#0d0d0d' },
  'hljs-attribute': { color: '#5d5d5d' },
  'hljs-symbol': { color: '#5d5d5d' },
  'hljs-bullet': { color: '#5d5d5d' },
  'hljs-addition': { color: '#0d0d0d', background: '#f1f1f1' },
  'hljs-deletion': { color: '#5d5d5d', background: '#f1f1f1' },
};

interface CodeBlockProps extends React.ComponentProps<'code'> {
  node?: unknown;
  inline?: boolean;
}

export function CodeBlock({
  node,
  inline = false,
  className = '',
  children,
  ...props
}: CodeBlockProps) {
  const [copied, setCopied] = useState(false);
  const match = /language-(\w+)/.exec(className || '');

  const code = String(children).trim();
  const language = match ? match[1] : '';

  const copyToClipboard = () => {
    navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  if (inline) {
    return (
      <code
        className={`rounded bg-[#f1f1f1] px-1 py-0.5 font-mono text-sm text-[#0d0d0d] ${className}`}
        {...props}
      >
        {children}
      </code>
    );
  }

  return (
    <span className="not-prose my-4 flex flex-col overflow-hidden rounded-[10px] border border-[#0000001a] bg-[#f9f9f9]">
      <span className="flex h-9 items-center justify-between border-b border-[#0000001a] px-3 text-xs text-[#8f8f8f]">
        <span>{language || 'code'}</span>
        <button
          type="button"
          onClick={copyToClipboard}
          className="flex h-7 items-center gap-1.5 rounded-lg px-2 text-[#5d5d5d] hover:bg-[#0000000d] hover:text-[#0d0d0d]"
          aria-label="Copy code"
        >
          <ClipboardIcon className="size-3.5" />
          <span>{copied ? 'Copied' : 'Copy'}</span>
        </button>
      </span>

      <SyntaxHighlighter
        style={graphiteTheme}
        language={language}
        PreTag="pre"
        className="max-w-full overflow-x-auto text-sm"
        wrapLongLines={false}
        showLineNumbers
        lineNumberStyle={{ color: '#8f8f8f', minWidth: '2.5em' }}
        customStyle={{
          margin: 0,
          padding: '1rem',
          borderRadius: 0,
          border: 0,
          backgroundColor: '#f9f9f9',
          color: '#0d0d0d',
          fontSize: '0.875rem',
          fontWeight: 400,
        }}
      >
        {code}
      </SyntaxHighlighter>
    </span>
  );
}
