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
    "What does the curator control?",
    "The curator address is fixed when a vault is deployed. It may rebalance an Active managed position within the contract’s coverage and cooldown limits, or call a shipped loss buffer. It cannot rewrite immutable vault terms.",
  ],
  [
    "When are transactions available?",
    "Deposits are available only during Subscription. Curator operations require the configured curator wallet and an Active vault. Redemptions open only after settlement. Disabled controls mean the contract conditions are not satisfied.",
  ],
];
export default function ResourcesPage() {
  return (
    <main className="appPage">
      <PageHeading
        label="The details matter"
        title="Resources"
        description="Clear terms. Better questions. A more informed first step."
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
          <Badge tone="red">Live contract guide</Badge>
          <h2>Vault documentation</h2>
          <p>
            Read the live state first, verify contract activity, then use only
            the transaction available for the current phase.
          </p>
          <Link href="/dashboard" className="downloadRow">
            <span>Vault state and lifecycle</span>
            <Badge>Open ↗</Badge>
          </Link>
          <Link href="/transparency" className="downloadRow">
            <span>Contracts, risks and returns</span>
            <Badge>Open ↗</Badge>
          </Link>
          <Link href="/activity" className="downloadRow">
            <span>Verified transaction history</span>
            <Badge>Open ↗</Badge>
          </Link>
          <Link href="/create" className="textButton">
            Curator operating conditions ↗
          </Link>
        </section>
      </div>
    </main>
  );
}
