{pkgs}:
pkgs.python3Packages.buildPythonPackage {
  pname = "haralyzer";
  version = "2.4.0";
  format = "setuptools";
  src = pkgs.fetchPypi {
    pname = "haralyzer";
    version = "2.4.0";
    sha256 = "1154162a328a5226bc6d1d9626be19536ae049dd44b0a160081054f4808326a5";
  };
  propagatedBuildInputs = with pkgs.python3Packages; [cached-property python-dateutil];
  patches = [./setup.patch];
}
