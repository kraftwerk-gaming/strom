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

  ldflags = [
    "-s"
    "-w"
    "-X github.com/filecoin-project/lassie/pkg/build.Version=${version}"
  ];

  doCheck = false;

  meta = {
    description = "Trustless content retriever for IPFS and Filecoin";
    homepage = "https://github.com/filecoin-project/lassie";
    license = lib.licenses.asl20;
    mainProgram = "lassie";
  };
}
