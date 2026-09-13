import { VaultDetail } from "@/components/app/vault-detail";
export default async function VaultPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ tranche?: string }>;
}) {
  const { id } = await params;
  const query = await searchParams;
  return (
    <VaultDetail
      id={id}
      initialTranche={query.tranche === "junior" ? "junior" : "senior"}
    />
  );
}
