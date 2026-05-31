import { brand } from '../data/tiles';
import styles from './Hero.module.css';

export default function Hero({ theme, onThemeToggle }) {
  return (
    <section className={styles.hero}>
      <div className={styles.topRow}>
        <button
          type="button"
          className={styles.themeBtn}
          onClick={onThemeToggle}
          aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
          title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
        >
          {theme === 'dark' ? (
            <svg viewBox="0 0 24 24" fill="currentColor" width="20" height="20" aria-hidden="true">
              <path d="M12 7a5 5 0 100 10A5 5 0 0012 7zm0-5a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm0 17a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM4.22 5.64a1 1 0 011.42-1.42l.7.71a1 1 0 01-1.41 1.41l-.71-.7zM17.66 18.36a1 1 0 011.42-1.42l.7.71a1 1 0 01-1.41 1.41l-.71-.7zM3 12a1 1 0 011-1h1a1 1 0 110 2H4a1 1 0 01-1-1zm16 0a1 1 0 011-1h1a1 1 0 110 2h-1a1 1 0 01-1-1zM4.22 18.36l-.71.7a1 1 0 01-1.41-1.41l.7-.71a1 1 0 011.42 1.42zM17.66 5.64l-.71.7a1 1 0 01-1.41-1.41l.7-.71a1 1 0 011.42 1.42z"/>
            </svg>
          ) : (
            <svg viewBox="0 0 24 24" fill="currentColor" width="20" height="20" aria-hidden="true">
              <path d="M21 12.79A9 9 0 1111.21 3a7 7 0 009.79 9.79z"/>
            </svg>
          )}
        </button>
      </div>

      <div className={styles.center}>
        <div className={styles.logoWrap}>
          <img
            className={styles.logo}
            src="/jackalope-still.png"
            alt="Jackalope mark"
          />
        </div>

        <div className={styles.text}>
          <h1 className={styles.name}>{brand.name}</h1>
          <p className={styles.tagline}>{brand.tagline}</p>
        </div>
      </div>

      <div className={styles.bio}>
        {brand.bio.map((para, i) => (
          <p key={i}>{para}</p>
        ))}
      </div>
    </section>
  );
}
