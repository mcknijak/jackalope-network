import Hero from './components/Hero';
import Tiles from './components/Tiles';
import Footer from './components/Footer';
import { useTheme } from './hooks/useTheme';
import { useTailnetProbe } from './hooks/useTailnetProbe';

export default function App() {
  const { theme, toggle } = useTheme();
  const tailnet = useTailnetProbe();

  return (
    <main className="page">
      <Hero theme={theme} onThemeToggle={toggle} />
      <Tiles tailnet={tailnet} />
      <Footer tailnet={tailnet} />
    </main>
  );
}
