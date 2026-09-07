import Image from "next/image";
import { ArrowMark, BrandMark } from "@/components/brand-mark";
import {
  HeroArtwork,
  Reveal,
  ScrollProgress,
} from "@/components/motion-elements";
import { RangeGraphic, WaterfallGraphic } from "@/components/product-graphics";

const principles = [
  {
    description:
      "Priority settlement and a defined cushion before loss reaches your capital.",
    index: "01",
    label: "Senior",
    outcome: "Protected yield",
  },
  {
    description:
      "First-loss exposure in return for the fees left after the senior claim is paid.",
    index: "02",
    label: "Junior",
    outcome: "Levered fees",
  },
  {
    description:
      "Fixed epochs make the protection visible, measurable, and honest at entry.",
    index: "03",
    label: "Epochs",
    outcome: "Known terms",
  },
] as const;

const steps = [
  [
    "Choose",
    "Pick the risk you actually want: payment priority or residual upside.",
  ],
  [
    "Fund",
    "Both sides subscribe against the same pool, range, and settlement date.",
  ],
  ["Settle", "At epoch close, value flows through one transparent waterfall."],
] as const;

export default function HomePage() {
  return (
    <main>
      <ScrollProgress />
      <header className="siteHeader">
        <a aria-label="Trelp home" className="logo" href="#top">
          <BrandMark />
          <span>TRELP</span>
        </a>
        <nav aria-label="Primary navigation">
          <a href="#structure">Structure</a>
          <a href="#mechanism">Mechanism</a>
          <a href="#risk">Risk</a>
        </nav>
        <a className="headerCta" href="/app">
          Launch app <ArrowMark />
        </a>
      </header>

      <section className="hero" id="top">
        <div className="heroCopy">
          <Reveal>
            <p className="kicker">Liquidity infrastructure / 001</p>
          </Reveal>
          <Reveal delay={0.08}>
            <h1>
              Liquidity,
              <br />
              divided by <em>risk.</em>
            </h1>
          </Reveal>
          <Reveal className="heroBottom" delay={0.16}>
            <p>
              One LP position. Two precise claims. Choose payment priority or
              take first loss for the residual upside.
            </p>
            <a className="button buttonDark" href="#structure">
              See the structure <ArrowMark />
            </a>
          </Reveal>
        </div>

        <div className="heroVisual">
          <span className="visualLabel">Risk, made legible</span>
          <HeroArtwork>
            <Image
              alt="Dithered medieval rider on horseback"
              fill
              priority
              sizes="(max-width: 800px) 100vw, 50vw"
              src="/trelp-rider.png"
            />
          </HeroArtwork>
          <svg aria-hidden="true" className="orbit" viewBox="0 0 640 640">
            <circle
              cx="320"
              cy="320"
              fill="none"
              r="250"
              stroke="currentColor"
              strokeDasharray="2 9"
            />
            <circle
              cx="320"
              cy="320"
              fill="none"
              r="196"
              stroke="currentColor"
            />
          </svg>
        </div>
      </section>

      <div className="ticker" aria-hidden="true">
        <div>
          SENIOR FIRST · JUNIOR RESIDUAL · FIXED EPOCHS · TRANSPARENT WATERFALL
          · SENIOR FIRST · JUNIOR RESIDUAL · FIXED EPOCHS · TRANSPARENT
          WATERFALL ·
        </div>
      </div>

      <section className="section" id="structure">
        <Reveal className="sectionIntro">
          <p className="sectionIndex">[ 01 / THE STRUCTURE ]</p>
          <h2>
            One market.
            <br />
            Two ways in.
          </h2>
          <p>
            LP returns bundle fee income and drawdown together. Trelp separates
            those claims so capital can choose its own place in the stack.
          </p>
        </Reveal>

        <div className="principleGrid">
          {principles.map((principle, index) => (
            <Reveal
              className="principle"
              delay={index * 0.08}
              key={principle.label}
            >
              <span>{principle.index}</span>
              <h3>{principle.label}</h3>
              <strong>{principle.outcome}</strong>
              <p>{principle.description}</p>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="redSection" id="mechanism">
        <Reveal className="sectionIntro sectionIntroLight">
          <p className="sectionIndex">[ 02 / THE MECHANISM ]</p>
          <h2>
            The waterfall
            <br />
            does the work.
          </h2>
        </Reveal>
        <div className="featureSplit">
          <Reveal className="graphicCard">
            <WaterfallGraphic />
          </Reveal>
          <Reveal className="featureCopy" delay={0.1}>
            <p className="kicker">Settlement order</p>
            <h3>Senior gets paid first. Junior owns what remains.</h3>
            <p>
              Every epoch closes against one NAV. The senior claim is resolved
              first; residual value belongs to junior. If value falls far
              enough, junior absorbs the loss before senior is impaired.
            </p>
            <a className="textLink" href="#risk">
              Read the risk boundary <ArrowMark />
            </a>
          </Reveal>
        </div>
      </section>

      <section className="section howSection">
        <Reveal className="sectionIntro compactIntro">
          <p className="sectionIndex">[ 03 / HOW IT WORKS ]</p>
          <h2>
            Three moves.
            <br />
            No mystery.
          </h2>
        </Reveal>
        <div className="steps">
          {steps.map(([title, description], index) => (
            <Reveal className="step" delay={index * 0.1} key={title}>
              <span>0{index + 1}</span>
              <h3>{title}</h3>
              <p>{description}</p>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="riskSection" id="risk">
        <Reveal className="riskCopy">
          <p className="sectionIndex">[ 04 / RISK, PLAINLY ]</p>
          <h2>
            Protection has
            <br />a visible edge.
          </h2>
          <p>
            Junior capital is a cushion, not a guarantee. A large gap, failed
            exit, oracle fault, or exhausted buffer can still impair senior.
            Trelp shows the boundary before capital enters.
          </p>
          <div className="riskStats">
            <div>
              <span>Range</span>
              <strong>Static per epoch</strong>
            </div>
            <div>
              <span>Terms</span>
              <strong>Known at entry</strong>
            </div>
            <div>
              <span>Returns</span>
              <strong>Never guaranteed</strong>
            </div>
          </div>
        </Reveal>
        <Reveal className="rangeCard" delay={0.1}>
          <RangeGraphic />
          <p>Illustrative range — parameters vary by vault.</p>
        </Reveal>
      </section>

      <section className="finalCta" id="vaults">
        <Reveal>
          <BrandMark className="ctaMark" />
          <p className="sectionIndex">[ CURATED MARKETS / COMING SOON ]</p>
          <h2>
            Pick your
            <br />
            <em>place in line.</em>
          </h2>
          <p>Starting with one transparent ETH / USDC epoch.</p>
          <a className="button buttonLight" href="/app">
            Explore vaults <ArrowMark />
          </a>
        </Reveal>
      </section>

      <footer>
        <a className="logo footerLogo" href="#top">
          <BrandMark />
          <span>TRELP</span>
        </a>
        <p className="footerTagline">Liquidity, divided by risk.</p>
        <p className="footerCopyright">© 2026 Trelp</p>
      </footer>
    </main>
  );
}
