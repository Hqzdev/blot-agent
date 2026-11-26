'use client';

import { TeyaLogo } from '@/components/teya-logo';
import { ArrowUp, Menu, X } from 'lucide-react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { FormEvent, useRef, useState } from 'react';
import styles from './landing-page.module.css';

const quickPrompts = [
  'Разобрать сложную тему',
  'Написать текст',
  'Провести исследование',
  'Попробовать Max',
];

const navigation = [
  { href: '#possibilities', label: 'Возможности' },
  { href: '#max', label: 'Teya Max' },
  { href: '#work', label: 'Для работы' },
  { href: '#about', label: 'О Teya' },
];

interface LandingPageProps {
  isAuthenticated: boolean;
}

export function LandingPage({ isAuthenticated }: LandingPageProps) {
  const router = useRouter();
  const promptInputRef = useRef<HTMLInputElement>(null);
  const [prompt, setPrompt] = useState('');
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const chatDestination = isAuthenticated ? '/chat' : '/register';

  const openChat = (value: string) => {
    const normalizedPrompt = value.trim();
    if (normalizedPrompt) {
      localStorage.setItem('input', normalizedPrompt);
    }
    router.push(chatDestination);
  };

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    openChat(prompt);
  };

  const selectPrompt = (value: string) => {
    setPrompt(value);
    promptInputRef.current?.focus();
  };

  return (
    <div className={styles.page}>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <Link
            className={styles.wordmark}
            href="/"
            aria-label="Teya — главная"
          >
            <TeyaLogo className={styles.logo} size={27} priority />
            <span>Teya</span>
          </Link>

          <nav className={styles.desktopNav} aria-label="Основная навигация">
            {navigation.map((item) => (
              <a key={item.href} href={item.href}>
                {item.label}
              </a>
            ))}
          </nav>

          <div className={styles.headerActions}>
            {isAuthenticated ? (
              <Link className={styles.ghostButton} href="/chat">
                Мой чат
              </Link>
            ) : (
              <Link className={styles.ghostButton} href="/login">
                Войти
              </Link>
            )}
            <Link className={styles.primaryButton} href={chatDestination}>
              Попробовать Teya ↗
            </Link>
          </div>

          <button
            type="button"
            className={styles.menuButton}
            aria-label={isMenuOpen ? 'Закрыть меню' : 'Открыть меню'}
            aria-expanded={isMenuOpen}
            onClick={() => setIsMenuOpen((current) => !current)}
          >
            {isMenuOpen ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>

        {isMenuOpen && (
          <nav className={styles.mobileNav} aria-label="Мобильная навигация">
            {navigation.map((item) => (
              <a
                key={item.href}
                href={item.href}
                onClick={() => setIsMenuOpen(false)}
              >
                {item.label}
              </a>
            ))}
            <Link href={chatDestination}>Попробовать Teya ↗</Link>
          </nav>
        )}
      </header>

      <main>
        <section className={styles.hero} aria-labelledby="hero-heading">
          <div className={styles.heroInner}>
            <p className={styles.eyebrow}>
              Персональный искусственный интеллект
            </p>
            <h1 id="hero-heading">Чем я могу помочь?</h1>
            <form className={styles.promptForm} onSubmit={handleSubmit}>
              <label className={styles.srOnly} htmlFor="landing-prompt">
                Сообщение для Teya
              </label>
              <input
                ref={promptInputRef}
                id="landing-prompt"
                value={prompt}
                onChange={(event) => setPrompt(event.target.value)}
                placeholder="Спросите Teya о чём угодно"
                autoComplete="off"
              />
              <button
                type="submit"
                aria-label="Перейти в чат"
                disabled={!prompt.trim()}
              >
                <ArrowUp size={21} strokeWidth={1.8} />
              </button>
            </form>
            <div className={styles.promptChips} aria-label="Примеры запросов">
              {quickPrompts.map((item) => (
                <button
                  key={item}
                  type="button"
                  onClick={() => selectPrompt(item)}
                >
                  {item}
                </button>
              ))}
            </div>
          </div>
        </section>

        <section
          className={styles.editorialSection}
          id="possibilities"
          aria-labelledby="editorial-heading"
        >
          <div className={styles.sectionHeading}>
            <p>В центре внимания</p>
            <h2 id="editorial-heading">
              Интеллект, который работает вместе с вами.
            </h2>
          </div>

          <div className={styles.editorialGrid}>
            <article className={styles.featuredStory} id="max">
              <div className={styles.featuredImage}>
                <Image
                  src="/landing/tarantula-nebula.jpg"
                  alt="Туманность Тарантул, снятая космическим телескопом James Webb"
                  fill
                  sizes="(max-width: 900px) 100vw, 760px"
                />
                <span>MAX</span>
              </div>
              <p className={styles.storyMeta}>Teya Max · Глубокое мышление</p>
              <h3>Думает глубже — и показывает путь к ответу.</h3>
              <p className={styles.storyDescription}>
                Для задач, где важен не только результат. Teya Max разбирает
                условия, проверяет предположения и показывает ход решения прямо
                в чате.
              </p>
              <p className={styles.imageCredit}>
                Изображение: NASA, ESA, CSA, STScI, Webb ERO Production Team
              </p>
            </article>

            <div className={styles.secondaryStories}>
              <article className={styles.secondaryStory}>
                <div className={styles.reasoningPreview}>
                  <div className={styles.previewHeader}>
                    <span>Teya V1 Max</span>
                    <span>В процессе</span>
                  </div>
                  <p className={styles.previewQuestion}>
                    Как выбрать лучший путь для запуска продукта?
                  </p>
                  <div className={styles.thought}>
                    <span>01</span>
                    <p>Определяю цель и ограничения</p>
                  </div>
                  <div className={styles.thought}>
                    <span>02</span>
                    <p>Сравниваю три возможные стратегии</p>
                  </div>
                  <div className={styles.thought}>
                    <span>03</span>
                    <p>Проверяю риски и формирую рекомендацию</p>
                  </div>
                </div>
                <p className={styles.storyMeta}>Прозрачный reasoning</p>
                <h3>Понимайте, как получен результат.</h3>
              </article>

              <article className={styles.secondaryStory}>
                <div className={styles.logoStage}>
                  <TeyaLogo className={styles.stageLogo} size={104} />
                  <span>Один диалог. Любая задача.</span>
                </div>
                <p className={styles.storyMeta}>Единое пространство</p>
                <h3>От первого вопроса до готовой работы.</h3>
              </article>
            </div>
          </div>
        </section>

        <section
          className={styles.capabilitiesSection}
          id="work"
          aria-labelledby="capabilities-heading"
        >
          <div className={styles.capabilitiesIntro}>
            <p>Как работает Teya</p>
            <h2 id="capabilities-heading">
              Один ассистент. Три способа двигаться дальше.
            </h2>
          </div>

          <div className={styles.capabilityList}>
            <article>
              <span>01</span>
              <h3>Отвечает</h3>
              <p>
                Быстро объясняет сложное, пишет, переводит и помогает принять
                решение без лишней подготовки.
              </p>
            </article>
            <article>
              <span>02</span>
              <h3>Исследует</h3>
              <p>
                Собирает контекст, структурирует материалы и превращает
                разрозненную информацию в ясный вывод.
              </p>
            </article>
            <article>
              <span>03</span>
              <h3>Рассуждает</h3>
              <p>
                В режиме Max уделяет задаче больше времени и открывает ход
                рассуждений для вашей проверки.
              </p>
            </article>
          </div>
        </section>

        <section className={styles.finalCta} id="about">
          <p>Teya создана, чтобы мысль быстрее становилась результатом.</p>
          <h2>Готовы начать?</h2>
          <Link className={styles.primaryButton} href={chatDestination}>
            Открыть Teya ↗
          </Link>
        </section>
      </main>

      <footer className={styles.footer}>
        <div className={styles.footerBrand}>
          <Link className={styles.wordmark} href="/">
            <TeyaLogo className={styles.logo} size={27} />
            <span>Teya</span>
          </Link>
          <p>Персональный искусственный интеллект.</p>
        </div>
        <div className={styles.footerLinks}>
          <div>
            <p>Продукт</p>
            <Link href="/chat">Чат</Link>
            <a href="#max">Teya Max</a>
            <a href="#possibilities">Возможности</a>
          </div>
          <div>
            <p>Компания</p>
            <a href="#about">О Teya</a>
            <Link href="/policy">Условия</Link>
            <Link href="/privacy">Конфиденциальность</Link>
          </div>
          <div>
            <p>Аккаунт</p>
            <Link href="/login">Войти</Link>
            <Link href="/register">Регистрация</Link>
          </div>
        </div>
        <p className={styles.copyright}>© 2026 Teya</p>
      </footer>
    </div>
  );
}
