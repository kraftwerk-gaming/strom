{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "lassie";
  version = "0.25.0";

  src = fetchFromGitHub {
    owner = "filecoin-project";
    repo = "lassie";
    rev = "v${version}";
    hash = "sha256-jNtBoa/RQ47j7spAZKwgaak1QFYW77K3sw7bYWDzH0g=";
  };

  vendorHash = "sha256-DDqH4eYLWnYGMW9GZW5qfHGD0ZvW95tiB7Oh6+5/oL4=";

  subPackages = [ "cmd/lassie" ];

  # Public IPFS gateways (ipfs.io, trustless-gateway.link, …) return 410 to
  # any User-Agent matching lassie/* — likely an anti-abuse measure on the
  # IPFS Foundation's Cloudflare. Replace the prefix so the UA is no longer
  # blocked. The version interpolation in fmt.Sprintf still runs, so the UA
  # ends up as "ipfs-fetch/v0.25.0-…".
  postPatch = ''
    substituteInPlace pkg/build/version.go \
      --replace-fail '"lassie/%s"' '"ipfs-fetch/%s"'
  '';

  # Lassie's version comes from a private lowercase `version` var in
  # pkg/build/version.go — the public `Version` is overwritten by init().
  ldflags = [
    "-s"
    "-w"
    "-X github.com/filecoin-project/lassie/pkg/build.version=v${version}"
  ];

  doCheck = false;

  meta = {
    description = "Trustless content retriever for IPFS and Filecoin";
    homepage = "https://github.com/filecoin-project/lassie";
    license = lib.licenses.asl20;
    mainProgram = "lassie";
  };
}
