import React, { memo } from 'react';
import ReactMarkdown, { type Components } from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { CodeBlock } from './code-block';

const components: Partial<Components> = {
  code: CodeBlock,
  pre: ({ children }) => <>{children}</>,
  ol: ({ node, children, ...props }) => {
    return (
      <ol
        className="my-4 ml-5 list-outside list-decimal space-y-1.5"
        {...props}
      >
        {children}
      </ol>
    );
  },
  li: ({ node, children, ...props }) => {
    return (
      <li className="pl-1 leading-7" {...props}>
        {children}
      </li>
    );
  },
  ul: ({ node, children, ...props }) => {
    return (
      <ul className="my-4 ml-5 list-outside list-disc space-y-1.5" {...props}>
        {children}
      </ul>
    );
  },
  strong: ({ node, children, ...props }) => {
    return (
      <span className="font-semibold" {...props}>
        {children}
      </span>
    );
  },
  a: ({ node, children, ...props }) => {
    return (
      <a
        className="font-medium text-[var(--chat-ink)] underline decoration-[var(--chat-hairline)] underline-offset-2 hover:decoration-[var(--chat-ink)]"
        target="_blank"
        rel="noreferrer"
        {...props}
      >
        {children}
      </a>
    );
  },
  h1: ({ node, children, ...props }) => {
    return (
      <h1 className="mb-2 mt-6 text-2xl font-semibold leading-8" {...props}>
        {children}
      </h1>
    );
  },
  h2: ({ node, children, ...props }) => {
    return (
      <h2 className="mb-2 mt-6 text-xl font-semibold leading-7" {...props}>
        {children}
      </h2>
    );
  },
  h3: ({ node, children, ...props }) => {
    return (
      <h3 className="mb-2 mt-5 text-lg font-semibold leading-7" {...props}>
        {children}
      </h3>
    );
  },
  h4: ({ node, children, ...props }) => {
    return (
      <h4 className="mb-2 mt-5 text-base font-semibold leading-6" {...props}>
        {children}
      </h4>
    );
  },
  h5: ({ node, children, ...props }) => {
    return (
      <h5 className="mb-2 mt-5 text-base font-semibold leading-6" {...props}>
        {children}
      </h5>
    );
  },
  h6: ({ node, children, ...props }) => {
    return (
      <h6 className="mb-2 mt-5 text-sm font-semibold leading-5" {...props}>
        {children}
      </h6>
    );
  },
  p: ({ node, children, ...props }) => {
    return (
      <p
        className="my-3 whitespace-pre-wrap leading-7 first:mt-0 last:mb-0"
        {...props}
      >
        {children}
      </p>
    );
  },
  blockquote: ({ node, children, ...props }) => {
    return (
      <blockquote
        className="my-4 border-l border-[var(--chat-hairline)] pl-4 text-[var(--chat-mid-ash)]"
        {...props}
      >
        {children}
      </blockquote>
    );
  },
  hr: ({ node, ...props }) => {
    return <hr className="my-6 border-[var(--chat-hairline)]" {...props} />;
  },
  table: ({ node, children, ...props }) => {
    return (
      <div className="my-4 overflow-x-auto rounded-[10px] border border-[var(--chat-hairline)]">
        <table className="w-full border-collapse text-sm" {...props}>
          {children}
        </table>
      </div>
    );
  },
  th: ({ node, children, ...props }) => {
    return (
      <th
        className="border-b border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] px-3 py-2 text-left font-semibold"
        {...props}
      >
        {children}
      </th>
    );
  },
  td: ({ node, children, ...props }) => {
    return (
      <td
        className="border-b border-[var(--chat-hairline)] px-3 py-2 align-top last:border-b-0"
        {...props}
      >
        {children}
      </td>
    );
  },
};

const remarkPlugins = [remarkGfm];

const NonMemoizedMarkdown = ({ children }: { children: string }) => {
  return (
    <ReactMarkdown remarkPlugins={remarkPlugins} components={components}>
      {children}
    </ReactMarkdown>
  );
};

export const Markdown = memo(
  NonMemoizedMarkdown,
  (prevProps, nextProps) => prevProps.children === nextProps.children,
);
