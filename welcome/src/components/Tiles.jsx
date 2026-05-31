import { tiles } from '../data/tiles';
import styles from './Tiles.module.css';

function Tile({ tile, disabled }) {
  const style = {
    '--tile-color': tile.color,
    '--icon-url': `url(${tile.icon})`,
  };
  const className = [
    styles.tile,
    disabled ? styles.tileDisabled : '',
  ]
    .filter(Boolean)
    .join(' ');

  const inner = (
    <>
      <div className={styles.iconWrap}>
        <div
          className={styles.icon}
          role="img"
          aria-label={`${tile.app} logo`}
        />
      </div>
      <div className={styles.meta}>
        <span className={styles.app}>{tile.app}</span>
        <span className={styles.role}>{tile.role}</span>
      </div>
      {disabled && (
        <span className={styles.lockBadge} aria-label="Tailnet only">
          <svg viewBox="0 0 24 24" fill="currentColor" width="12" height="12" aria-hidden="true">
            <path d="M12 1a5 5 0 00-5 5v3H6a2 2 0 00-2 2v10a2 2 0 002 2h12a2 2 0 002-2V11a2 2 0 00-2-2h-1V6a5 5 0 00-5-5zm-3 8V6a3 3 0 116 0v3H9z"/>
          </svg>
          tailnet only
        </span>
      )}
    </>
  );

  if (disabled) {
    return (
      <div
        className={className}
        style={style}
        aria-disabled="true"
        title="Only reachable from devices on the tailnet"
      >
        {inner}
      </div>
    );
  }

  return (
    <a
      className={className}
      style={style}
      href={tile.href}
      target="_blank"
      rel="noopener noreferrer"
    >
      {inner}
    </a>
  );
}

export default function Tiles({ tailnet }) {
  const offTailnet = tailnet === 'offline';
  const pending = tailnet === 'pending';
  const disabled = offTailnet || pending;

  return (
    <section className={styles.section}>
      <p className="section-label">Services</p>
      <h2 className="section-title">What's running here</h2>

      <div className={styles.grid}>
        {tiles.map((tile) => (
          <Tile key={tile.id} tile={tile} disabled={disabled} />
        ))}
      </div>
    </section>
  );
}
