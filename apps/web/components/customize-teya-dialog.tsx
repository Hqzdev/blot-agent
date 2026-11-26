'use client';

import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { useEffect, useState } from 'react';

const TRAITS = [
  'Bold',
  'Witty',
  'Honest',
  'Encouraging',
  'Gen Z',
  'Skeptical',
  'Traditional',
  'Visionary',
  'Poetic',
];

export function CustomizeTeyaDialog({
  open,
  onOpenChange,
}: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const [nickname, setNickname] = useState('');
  const [occupation, setOccupation] = useState('');
  const [traits, setTraits] = useState<string[]>([]);
  const [additional, setAdditional] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (open) {
      setLoading(true);
      fetch('/app/api/user-profile')
        .then((res) => res.json())
        .then((data) => {
          const customization = data.customization || {};
          setNickname(customization.nickname || '');
          setOccupation(customization.occupation || '');
          setTraits(customization.traits || []);
          setAdditional(customization.additional || '');
        })
        .catch(() => undefined)
        .finally(() => setLoading(false));
    }
  }, [open]);

  const handleSave = async () => {
    setLoading(true);
    const customization = {
      nickname,
      occupation,
      traits,
      additional,
    };
    try {
      const res = await fetch('/app/api/user-profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ customization }),
      });
      if (!res.ok) {
        throw new Error('Unable to save customization');
      }
      onOpenChange(false);
    } catch {
      setLoading(false);
    } finally {
      setLoading(false);
    }
  };

  const toggleTrait = (trait: string) => {
    setTraits((prev) =>
      prev.includes(trait) ? prev.filter((t) => t !== trait) : [...prev, trait],
    );
  };

  const isAnyFieldFilled = Boolean(
    nickname || occupation || traits.length > 0 || additional,
  );

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] overflow-y-auto rounded-[10px] border-border bg-background text-foreground shadow-none sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle className="text-2xl font-medium">
            Customize Teya
          </DialogTitle>
          <DialogDescription className="text-muted-foreground">
            Introduce yourself to get more personalized answers from Teya.
          </DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            handleSave();
          }}
        >
          <div>
            <label
              htmlFor="customize-nickname"
              className="mb-1 block text-sm font-medium"
            >
              How should Teya address you?
            </label>
            <input
              id="customize-nickname"
              type="text"
              className="w-full rounded-[10px] border border-input bg-background px-3 py-2 text-sm text-foreground outline-none focus:border-ring"
              placeholder="Nickname"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              maxLength={80}
            />
          </div>
          <div>
            <label
              htmlFor="customize-occupation"
              className="mb-1 block text-sm font-medium"
            >
              What is your occupation?
            </label>
            <input
              id="customize-occupation"
              type="text"
              className="w-full rounded-[10px] border border-input bg-background px-3 py-2 text-sm text-foreground outline-none focus:border-ring"
              placeholder="e.g. Student at Waterloo University"
              value={occupation}
              onChange={(e) => setOccupation(e.target.value)}
              maxLength={160}
            />
          </div>
          <div>
            <label
              htmlFor="customize-traits"
              className="mb-1 block text-sm font-medium"
            >
              What personality traits should Teya have?
            </label>
            <div className="flex flex-wrap gap-2" id="customize-traits">
              {TRAITS.map((trait) => (
                <button
                  type="button"
                  key={trait}
                  className={`rounded-[10px] border px-3 py-1 text-sm ${traits.includes(trait) ? 'border-primary bg-primary text-primary-foreground' : 'border-border bg-muted text-muted-foreground hover:bg-accent'}`}
                  onClick={() => toggleTrait(trait)}
                >
                  {trait}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label
              htmlFor="customize-additional"
              className="mb-1 block text-sm font-medium"
            >
              Anything else Teya should know about you?
            </label>
            <textarea
              id="customize-additional"
              className="w-full resize-none rounded-[10px] border border-input bg-background px-3 py-2 text-sm text-foreground outline-none focus:border-ring"
              placeholder="Interests, values, or preferences to remember"
              value={additional}
              onChange={(e) => setAdditional(e.target.value)}
              rows={3}
              maxLength={4000}
            />
          </div>
          <div className="mt-6 flex justify-end gap-2">
            <Button
              type="button"
              variant="ghost"
              onClick={() => onOpenChange(false)}
            >
              Cancel
            </Button>
            <Button
              className={
                isAnyFieldFilled
                  ? 'rounded-[10px] bg-primary text-primary-foreground hover:bg-primary/90'
                  : 'cursor-not-allowed rounded-[10px] bg-muted text-muted-foreground'
              }
              type="submit"
              disabled={loading || !isAnyFieldFilled}
            >
              {loading ? 'Saving...' : 'Save'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  );
}
