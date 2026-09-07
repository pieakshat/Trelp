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
    description: "Gets paid first from the available vault value.",
    label: "Senior",
    outcome: "Lower risk",
  },
  {
    description: "Takes the first loss and receives the value that remains.",
    label: "Junior",
    outcome: "Higher upside",
  },
  {
    description: "Uses one pool, one price range, and one end date.",
    label: "Shared vault",
    outcome: "Same market",
  },
] as const;

const steps = [
  ["Choose", "Choose Senior for lower risk or Junior for more upside."],
  ["Deposit", "Add funds to one shared LP vault."],
  ["Settle", "At the end date, Senior gets paid first. Junior gets the rest."],
] as const;

const vaultFacts = [
  ["Risk level", "Senior or Junior"],
  ["Loss buffer", "The amount Junior covers first"],
  ["End date", "The date when the vault settles"],
  ["Payment order", "Who gets paid first"],
] as const;

const questions = [
  [
    "What is a tranched LP vault?",
    "It is one LP position split into Senior and Junior risk levels.",
  ],
  [
    "What does Senior receive?",
    "Senior receives payment first from the available vault value.",
  ],
  [
    "What does Junior receive?",
    "Junior takes the first loss and receives the value left after Senior is paid.",
  ],
  [
    "Can I lose money?",
    "Yes. The loss buffer can reduce risk, but it cannot remove all risk.",
  ],
] as const;

const tickerText =
  "SENIOR FIRST · JUNIOR RESIDUAL · FIXED EPOCHS · TRANSPARENT WATERFALL ·";
const tickerItems = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "six",
  "seven",
  "eight",
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
            <p className="kicker">A simpler way to choose LP risk</p>
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
              One LP position has two risk levels. Choose lower risk or more
              upside.
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
              src="/trelp-rider-transparent.png"
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
        <div className="tickerTrack">
          {["first", "second"].map((group) => (
            <div className="tickerGroup" key={group}>
              {tickerItems.map((item) => (
                <span key={`${group}-${item}`}>{tickerText}</span>
              ))}
            </div>
          ))}
        </div>
      </div>

      <section className="section" id="structure">
        <Reveal className="sectionIntro">
          <div>
            <p className="sectionLabel">Two risk levels</p>
            <h2>
              One pool.
              <br />
              Two choices.
            </h2>
          </div>
          <p>
            Trelp splits one LP position into Senior and Junior. You choose the
            risk level that fits you.
          </p>
        </Reveal>

        <div className="principleGrid">
          {principles.map((principle, index) => (
            <Reveal
              className="principle"
              delay={index * 0.08}
              key={principle.label}
            >
              <h3>{principle.label}</h3>
              <strong>{principle.outcome}</strong>
              <p>{principle.description}</p>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="redSection" id="mechanism">
        <Reveal className="sectionIntro sectionIntroLight">
          <div>
            <p className="sectionLabel">Payment order</p>
            <h2>
              Senior first.
              <br />
              Junior next.
            </h2>
          </div>
          <p>Both risk levels use the same vault value and end date.</p>
        </Reveal>
        <div className="featureSplit">
          <Reveal className="graphicCard">
            <WaterfallGraphic />
          </Reveal>
          <Reveal className="featureCopy" delay={0.1}>
            <p className="kicker">Settlement order</p>
            <h3>Senior gets paid first. Junior gets the rest.</h3>
            <p>
              The vault uses one final value. Senior receives payment first.
              Junior receives the value that remains and takes the first loss.
            </p>
            <a className="textLink" href="#risk">
              Read the risk boundary <ArrowMark />
            </a>
          </Reveal>
        </div>
      </section>

      <section className="section howSection">
        <Reveal className="sectionIntro compactIntro">
          <p className="sectionLabel">How it works</p>
          <h2>
            Choose.
            <br />
            Deposit. Settle.
          </h2>
        </Reveal>
        <div className="steps">
          {steps.map(([title, description], index) => (
            <Reveal className="step" delay={index * 0.1} key={title}>
              <h3>{title}</h3>
              <p>{description}</p>
            </Reveal>
          ))}
        </div>
      </section>

      <section className="riskSection" id="risk">
        <Reveal className="riskCopy">
          <p className="sectionLabel">Risk</p>
          <h2>
            Know where
            <br /> protection ends.
          </h2>
          <p>
            Junior funds cover losses first. This buffer can run out. Senior
            funds can still lose value.
          </p>
          <div className="riskStats">
            <div>
              <span>Range</span>
              <strong>Fixed for each vault</strong>
            </div>
            <div>
              <span>Terms</span>
              <strong>Shown before deposit</strong>
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

      <section className="claritySection">
        <Reveal className="clarityIntro">
          <p className="sectionLabel">What you see</p>
          <h2>Know the terms before you deposit.</h2>
          <p>Each vault shows the facts that affect your risk and return.</p>
        </Reveal>
        <dl className="clarityGrid">
          {vaultFacts.map(([term, description], index) => (
            <Reveal delay={index * 0.06} key={term}>
              <dt>{term}</dt>
              <dd>{description}</dd>
            </Reveal>
          ))}
        </dl>
      </section>

      <section className="faqSection">
        <Reveal className="faqIntro">
          <p className="sectionLabel">Questions</p>
          <h2>Clear answers.</h2>
        </Reveal>
        <div className="faqList">
          {questions.map(([question, answer]) => (
            <details key={question}>
              <summary>{question}</summary>
              <p>{answer}</p>
            </details>
          ))}
        </div>
      </section>

      <section className="finalCta" id="vaults">
        <Reveal>
          <BrandMark className="ctaMark" />
          <p className="sectionLabel">Explore the first markets</p>
          <h2>
            Choose your
            <br />
            <em>risk level.</em>
          </h2>
          <p>Compare Senior and Junior vaults in one place.</p>
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
