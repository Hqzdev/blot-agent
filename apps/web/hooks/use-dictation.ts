'use client';

import { useCallback, useEffect, useRef, useState } from 'react';

interface SpeechRecognitionResultItem {
  transcript: string;
}

interface SpeechRecognitionResult {
  0: SpeechRecognitionResultItem;
}

interface SpeechRecognitionResultEvent extends Event {
  resultIndex: number;
  results: ArrayLike<SpeechRecognitionResult>;
}

interface SpeechRecognitionInstance {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  onend: (() => void) | null;
  onerror: (() => void) | null;
  onresult: ((event: SpeechRecognitionResultEvent) => void) | null;
  start: () => void;
  stop: () => void;
}

type SpeechRecognitionConstructor = new () => SpeechRecognitionInstance;

type SpeechRecognitionWindow = Window & {
  SpeechRecognition?: SpeechRecognitionConstructor;
  webkitSpeechRecognition?: SpeechRecognitionConstructor;
};

export function useDictation({
  onError,
  onTranscript,
}: {
  onError: (message: string) => void;
  onTranscript: (transcript: string) => void;
}) {
  const recognitionRef = useRef<SpeechRecognitionInstance | null>(null);
  const [isListening, setIsListening] = useState(false);

  const stop = useCallback(() => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
    setIsListening(false);
  }, []);

  const toggle = useCallback(() => {
    if (recognitionRef.current) {
      stop();
      return;
    }

    const speechWindow = window as SpeechRecognitionWindow;
    const Recognition =
      speechWindow.SpeechRecognition || speechWindow.webkitSpeechRecognition;

    if (!Recognition) {
      onError('Voice input is not supported in this browser');
      return;
    }

    const recognition = new Recognition();
    recognition.continuous = true;
    recognition.interimResults = false;
    recognition.lang = navigator.language || 'en-US';
    recognition.onresult = (event) => {
      const transcripts: string[] = [];
      for (
        let index = event.resultIndex;
        index < event.results.length;
        index++
      ) {
        transcripts.push(event.results[index][0].transcript);
      }
      const transcript = transcripts.join(' ').trim();
      if (transcript) {
        onTranscript(transcript);
      }
    };
    recognition.onerror = () => {
      recognitionRef.current = null;
      setIsListening(false);
      onError('Voice input stopped unexpectedly');
    };
    recognition.onend = () => {
      recognitionRef.current = null;
      setIsListening(false);
    };
    recognitionRef.current = recognition;
    recognition.start();
    setIsListening(true);
  }, [onError, onTranscript, stop]);

  useEffect(() => stop, [stop]);

  return { isListening, toggle };
}
