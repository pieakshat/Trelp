import Image from "next/image";
import Link from "next/link";
import { Badge, PageHeading } from "@/components/app/ui";

const questions = [
  [
    "How does wallet connection work?",
    "Trelp connects to an Ethereum wallet installed in your browser, or the built-in browser of a mobile wallet. Choose your account, select a supported network, then sign a message to verify ownership. Signing in does not grant token approvals or cost gas.",
  ],
  [
    "Which balances are real?",
    "The wallet card reads native ETH from your selected network. Vault funding, claim-token balances, position value, deposits and redemptions come from the configured contracts and RPC.",
  ],
  [
    "What does the Senior buffer cover?",
    "Junior takes losses first. The listed buffer is the Junior share that can absorb losses before Senior principal is affected. Large enough losses can reach both tranches; no return is guaranteed.",
  ],
  [
    "What is saved when I create a vault?",
    "A local draft of the market, duration, capacity and risk split. A signed-in wallet can request a server-side validation of those terms. Neither step deploys a contract or publishes a live vault.",
  ],
  [
    "Can I use the factsheet for another vault?",
    "Yes. The Word template is editable. Replace the illustrated terms with the terms you have verified for your vault, record your assumptions and review the final version before sharing it.",
  ],
];
export default function ResourcesPage() {
  return (
    <main className="appPage">
      <PageHeading
        label="The details matter"
        title="Resources"
        description="Clear terms. Better questions. A more informed first step."
        action={
          <Link href="/create" className="uiButton secondary">
            Create a vault draft ↗
          </Link>
        }
      />
      <section className="resourcesHero">
        <div>
          <Badge tone="red">Vault toolkit</Badge>
          <h2>
            Know what
            <br />
            you’re stepping into.
          </h2>
          <p>
            A concise factsheet for comparing terms, understanding the payment
            order and recording your own review.
          </p>
          <div className="inlineActions">
            <a
              href="/documents/trelp-vault-factsheet.pdf"
              className="uiButton"
              target="_blank"
              rel="noreferrer"
            >
              Open factsheet PDF ↗
            </a>
            <a
              href="/documents/trelp-vault-factsheet.docx"
              download
              className="uiButton secondary"
            >
              Download Word template ↓
            </a>
          </div>
          <small>
            Editable education template · verify every term on-chain
          </small>
        </div>
        <Image
          src="/brand/vault-structure.svg"
          width={460}
          height={280}
          alt="Layered illustration of the Senior and Junior vault structure"
        />
      </section>
      <div className="resourceColumns">
        <section className="panel">
          <div className="panelHead">
            <div>
              <h2>A few things worth understanding.</h2>
              <p>How the workspace, wallet and vault terms fit together</p>
            </div>
          </div>
          <div className="resourceFaq">
            {questions.map(([title, body]) => (
              <details key={title}>
                <summary>
                  {title}
                  <span aria-hidden="true">+</span>
                </summary>
                <p>{body}</p>
              </details>
            ))}
          </div>
        </section>
        <section className="panel brandDownloads">
          <Image
            src="/brand/trelp-logo.svg"
            width={168}
            height={39}
            alt="Trelp"
          />
          <h2>The Trelp asset kit.</h2>
          <p>
            The original mark, ready to use. Vector assets stay sharp at every
            size.
          </p>
          <a href="/brand/trelp-logo.svg" download className="downloadRow">
            <span>Primary wordmark</span>
            <Badge>SVG ↓</Badge>
          </a>
          <a href="/brand/trelp-mark.svg" download className="downloadRow">
            <span>Brand symbol</span>
            <Badge>SVG ↓</Badge>
          </a>
          <a href="/brand/vault-structure.svg" download className="downloadRow">
            <span>Vault illustration</span>
            <Badge>SVG ↓</Badge>
          </a>
          <a
            href="/brand/asset-sources.txt"
            className="textButton"
            target="_blank"
            rel="noreferrer"
          >
            Token logo sources ↗
          </a>
        </section>
      </div>
    </main>
  );
}
