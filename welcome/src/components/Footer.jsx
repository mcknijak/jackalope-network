import { brand } from '../data/tiles';
import styles from './Footer.module.css';

export default function Footer({ tailnet }) {
  return (
    <footer className={styles.footer}>
      <div className={styles.mark}>
        <img
          src="/favicon.png"
          alt=""
          className={styles.markLogo}
          aria-hidden="true"
        />
        <span className={styles.markText}>jackalope.network</span>
      </div>

      <div className={styles.row}>
        <a href={brand.portfolio} target="_blank" rel="noopener noreferrer">
          jackmcknight.dev
        </a>
        <span className={styles.dot} aria-hidden="true" />
        <a href={brand.repo} target="_blank" rel="noopener noreferrer">
          repo on github
        </a>
        <span className={styles.dot} aria-hidden="true" />
        <span className={styles.status} data-state={tailnet}>
          {tailnet === 'online'  && 'on tailnet: all apps live'}
          {tailnet === 'offline' && 'off tailnet: apps are private'}
          {tailnet === 'pending' && 'checking tailnet...'}
        </span>
      </div>
    </footer>
  );
}
