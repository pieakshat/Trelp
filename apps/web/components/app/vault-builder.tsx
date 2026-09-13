"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { reviewVaultDraft } from "@/app/actions/vaults";
import {
  type DraftInput,
  dateLabel,
  draftSchema,
  money,
} from "@/lib/local-data";
import { useAppStore } from "@/stores/app-store";
import { AssetMark, Badge, NetworkMark, PageHeading } from "./ui";
import { useWallet, WalletButton } from "./wallet-provider";

export function VaultBuilder() {
  const { session } = useWallet();
  const drafts = useAppStore((s) => s.drafts);
  const saveDraft = useAppStore((s) => s.saveDraft);
  const removeDraft = useAppStore((s) => s.removeDraft);
  const [form, setForm] = useState({
    name: "",
    asset: "ETH / USDC",
    network: "Ethereum",
    duration: "30",
    buffer: "30",
    capacity: "100000",
    riskAccepted: false,
  });
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [pending, setPending] = useState(false);
  const [review, setReview] = useState<DraftInput | null>(null);
  const [reviewedBy, setReviewedBy] = useState("");
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const dialog = useRef<HTMLDialogElement>(null);
  const deleteDialog = useRef<HTMLDialogElement>(null);
  const previewBuffer = Math.min(50, Math.max(10, Number(form.buffer) || 10));
  const previewCapacity = Math.min(
    10000000,
    Math.max(10000, Number(form.capacity) || 10000),
  );
  function prepare() {
    setError("");
    setMessage("");
    setReviewedBy("");
    const result = draftSchema.safeParse(form);
    if (!result.success) {
      setError(result.error.issues[0]?.message ?? "Check the form.");
      return;
    }
    setReview(result.data);
    dialog.current?.showModal();
  }
  async function authenticateReview() {
    if (!review || pending) return;
    if (!session) {
      setError("Sign in with your wallet to review a vault draft.");
      return;
    }
    setPending(true);
    setError("");
    try {
      const result = await reviewVaultDraft(review);
      if (result.ok) setReviewedBy(result.reviewedBy);
      else setError(result.error);
    } catch {
      setError("The server could not review the draft. Try again.");
    } finally {
      setPending(false);
    }
  }
  function save() {
    if (!review || pending) return;
    try {
      saveDraft(review);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save draft.");
      return;
    }
    dialog.current?.close();
    setReview(null);
    setForm({ ...form, name: "", riskAccepted: false });
    setMessage("Draft saved in this browser. You can review it below.");
  }
  return (
    <main className="appPage">
      <PageHeading
        label="Curator workspace"
        title="Create vault"
        description="Define curator terms and save a local draft. This screen does not deploy a contract."
        action={
          <Link href="/dashboard" className="uiButton secondary">
            Open dashboard
          </Link>
        }
      />
      <section
        className="workspaceIdentity"
        aria-label="Draft market and network"
      >
        <div>
          <AssetMark asset={form.asset} />
          <strong>{form.asset}</strong>
        </div>
        <NetworkMark network={form.network} />
      </section>
      <div className="builderColumns">
        <section className="panel">
          <div className="panelHead">
            <h2>Vault details</h2>
            <Badge>Local draft only</Badge>
          </div>
          <form
            className="panelBody"
            onSubmit={(e) => {
              e.preventDefault();
              prepare();
            }}
          >
            <label className="field">
              Vault name
              <input
                required
                maxLength={60}
                placeholder="For example, ETH monthly income"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </label>
            <div className="formGrid">
              <label className="field">
                Asset pair
                <select
                  value={form.asset}
                  onChange={(e) => setForm({ ...form, asset: e.target.value })}
                >
                  <option>ETH / USDC</option>
                  <option>WBTC / USDC</option>
                  <option>USDC / USDT</option>
                </select>
              </label>
              <label className="field">
                Network
                <select
                  value={form.network}
                  onChange={(e) =>
                    setForm({ ...form, network: e.target.value })
                  }
                >
                  <option>Ethereum</option>
                  <option>Base</option>
                </select>
              </label>
              <label className="field">
                Term
                <select
                  value={form.duration}
                  onChange={(e) =>
                    setForm({ ...form, duration: e.target.value })
                  }
                >
                  <option value="14">14 days</option>
                  <option value="30">30 days</option>
                  <option value="90">90 days</option>
                </select>
              </label>
              <label className="field">
                Capacity (USDC)
                <input
                  type="number"
                  min="10000"
                  max="10000000"
                  step="1"
                  required
                  value={form.capacity}
                  onChange={(e) =>
                    setForm({ ...form, capacity: e.target.value })
                  }
                />
              </label>
            </div>
            <label className="field">
              Junior loss buffer (%)
              <input
                type="number"
                min="10"
                max="50"
                step="1"
                required
                value={form.buffer}
                onChange={(e) => setForm({ ...form, buffer: e.target.value })}
              />
              <small>Between 10% and 50% of the pool.</small>
            </label>
            <label className="checkRow">
              <input
                type="checkbox"
                checked={form.riskAccepted}
                onChange={(e) =>
                  setForm({ ...form, riskAccepted: e.target.checked })
                }
              />
              <span>
                I understand that both risk levels can lose money. This draft
                does not deploy a contract.
              </span>
            </label>
            {error && !review && (
              <p role="alert" className="uiError">
                {error}
              </p>
            )}
            {message && (
              <p className="uiSuccess" role="status">
                {message}
              </p>
            )}
            <button className="uiButton" type="submit">
              Review draft →
            </button>
          </form>
        </section>
        <aside className="panel builderPreview">
          <div className="panelHead">
            <h2>Capital split</h2>
          </div>
          <div className="panelBody">
            <div className="splitBar">
              <span
                style={{
                  width: `${100 - previewBuffer}%`,
                }}
              >
                Senior
              </span>
              <span>Junior</span>
            </div>
            <dl className="termList">
              <div>
                <dt>Senior share</dt>
                <dd>{100 - previewBuffer}%</dd>
              </div>
              <div>
                <dt>Junior share</dt>
                <dd>{Number(form.buffer) || 0}%</dd>
              </div>
              <div>
                <dt>Senior capacity</dt>
                <dd>
                  {money((previewCapacity * (100 - previewBuffer)) / 100)}
                </dd>
              </div>
              <div>
                <dt>Junior capacity</dt>
                <dd>{money((previewCapacity * previewBuffer) / 100)}</dd>
              </div>
            </dl>
            <p className="uiNotice">
              Senior receives payment first. Junior receives what remains and
              takes the first loss.
            </p>
            <p className="footnote">
              These are product terms for a local draft. They are not deployable
              protocol parameters.
            </p>
          </div>
        </aside>
      </div>
      <section className="panel sectionGap">
        <div className="panelHead">
          <div>
            <h2>Saved drafts</h2>
            <p>
              {drafts.length} local {drafts.length === 1 ? "draft" : "drafts"}
            </p>
          </div>
        </div>
        {drafts.length ? (
          <div className="tableWrap">
            <table className="dataTable">
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Market</th>
                  <th scope="col">Term</th>
                  <th scope="col">Capacity</th>
                  <th scope="col">Created</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {drafts.map((d) => (
                  <tr key={d.id}>
                    <td>
                      <strong>{d.name}</strong>
                      <small>Local curator draft</small>
                    </td>
                    <td>
                      {d.asset}
                      <small>{d.network}</small>
                    </td>
                    <td>{d.duration} days</td>
                    <td>{money(d.capacity)}</td>
                    <td>{dateLabel(d.createdAt)}</td>
                    <td>
                      <button
                        type="button"
                        className="textButton"
                        onClick={() => {
                          setForm({
                            name: d.name,
                            asset: d.asset,
                            network: d.network,
                            duration: String(d.duration),
                            buffer: String(d.buffer),
                            capacity: String(d.capacity),
                            riskAccepted: false,
                          });
                          setMessage(
                            "Draft copied to the form. Save it as a new version.",
                          );
                          window.scrollTo({ top: 0, behavior: "smooth" });
                        }}
                      >
                        Duplicate
                      </button>
                      <button
                        type="button"
                        className="textButton danger"
                        aria-label={`Remove ${d.name}`}
                        onClick={() => {
                          setDeleteId(d.id);
                          deleteDialog.current?.showModal();
                        }}
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <div className="uiEmpty">
            <h3>No drafts yet</h3>
            <p>Review the form to save your first local draft.</p>
          </div>
        )}
      </section>
      <dialog
        aria-labelledby="draft-review-title"
        onCancel={(e) => {
          if (pending) e.preventDefault();
        }}
        className="appDialog"
        ref={dialog}
        onClose={() => {
          setReview(null);
          setError("");
        }}
      >
        <div className="dialogHead">
          <h2 id="draft-review-title">Review vault draft</h2>
          <button
            type="button"
            aria-label="Close vault review"
            disabled={pending}
            onClick={() => dialog.current?.close()}
          >
            ×
          </button>
        </div>
        <dl className="termList">
          <div>
            <dt>Name</dt>
            <dd>{review?.name}</dd>
          </div>
          <div>
            <dt>Market</dt>
            <dd>{review?.asset}</dd>
          </div>
          <div>
            <dt>Term</dt>
            <dd>{review?.duration} days</dd>
          </div>
          <div>
            <dt>Junior share</dt>
            <dd>{review?.buffer}%</dd>
          </div>
          <div>
            <dt>Capacity</dt>
            <dd>{money(review?.capacity ?? 0)}</dd>
          </div>
        </dl>
        <p className="muted">
          Save a local draft, or sign in and request an authenticated server
          review.
        </p>
        <WalletButton />
        {reviewedBy && reviewedBy === session?.address && (
          <p className="uiSuccess" role="status">
            Server review passed for {reviewedBy.slice(0, 6)}…
            {reviewedBy.slice(-4)}.
          </p>
        )}
        {error && (
          <p className="uiError" role="alert">
            {error}
          </p>
        )}
        <div className="dialogActions">
          <button
            className="uiButton secondary"
            type="button"
            disabled={pending}
            onClick={authenticateReview}
          >
            {pending ? "Reviewing…" : "Request server review"}
          </button>
          <button
            className="uiButton"
            type="button"
            disabled={pending}
            onClick={save}
          >
            Save local draft
          </button>
        </div>
      </dialog>
      <dialog
        aria-labelledby="draft-delete-title"
        className="appDialog"
        ref={deleteDialog}
      >
        <h2 id="draft-delete-title">Remove this draft?</h2>
        <p>This removes the local draft. It does not change any live vault.</p>
        <div className="dialogActions">
          <button
            className="uiButton secondary"
            type="button"
            onClick={() => deleteDialog.current?.close()}
          >
            Cancel
          </button>
          <button
            className="uiButton"
            type="button"
            onClick={() => {
              if (deleteId) removeDraft(deleteId);
              deleteDialog.current?.close();
              setDeleteId(null);
            }}
          >
            Remove draft
          </button>
        </div>
      </dialog>
    </main>
  );
}
