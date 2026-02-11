from dataclasses import dataclass
from dataclasses import field
from typing import List, Dict, Union, Literal
from pydantic import BaseModel, RootModel, Field


@dataclass
class ProjectInfo:
    url: Union[str, int, List, None] = "n/a"
    commit_id: Union[str, int, List, None] = "n/a"
    address: Union[str, List, None] = field(default_factory=lambda: "n/a")
    chain: Union[str, int, List, None] = "n/a"
    compiler_version: Union[str, List, None] = "n/a"
    audit_date: str = "n/a"
    project_path: Union[str, Dict, None] = "n/a"

    def is_empty(self):
        if (self.url == "n/a" and self.address == "n/a") or (
            not self.url and not self.address
        ):
            return True
        return False


@dataclass
class Finding:
    id: Union[str, int] = 0
    category: Dict = field(default_factory=dict)
    title: str = ""
    description: str = ""
    severity: Union[str, List, None] = field(default_factory=lambda: "")
    location: Union[str, List, None] = field(default_factory=lambda: "")
    files: Union[str, List, None] = field(default_factory=list)


class CWE(BaseModel):
    ID: int
    Name: str
    Description: str = ""
    Abstraction: Literal["Pillar", "Class", "Base", "Variant", "Compound"]
    Mapping: Literal["Allowed", "Allowed-with-Review", "Discouraged", "Prohibited"]
    Peer: List = Field(default_factory=list)
    Parent: List = Field(default_factory=list)
    Child: List[int] = Field(default_factory=list)

    def __str__(self) -> str:
        return f"CWE-{self.ID}: {self.Name}"

    def __hash__(self):
        return hash(str(self))

    def add_child(self, child_cwe: "CWE"):
        self.Child.append(child_cwe)
        child_cwe.Parent.append(self)


class CWEDatabase(RootModel):
    root: Dict[str, CWE]

    def get_by_id(self, id: int | str):
        name = f"CWE-{id}"
        return self.root[name]

    def get_by_name(self, name: str):
        return self.root[name]


class Report(BaseModel):
    path: str = ""
    project_info: ProjectInfo = field(default_factory=ProjectInfo)
    findings: List[Finding] = field(default_factory=list)

    def __hash__(self):
        return hash((self.path, self.project_info, tuple(self.findings)))

    def append_finding(self, finding: Finding):
        self.findings.append(finding)


class VulnerabilityFilePair(BaseModel):
    vfp_id: str = ""  # Unique ID for the VulnerabilityFilePair, e.g., 'vfp_00001'
    project_name: str = ""
    findings: List[Finding] = Field(default_factory=list)
    affected_files: Dict[str, str] = Field(default_factory=dict)

    def __hash__(self):
        return hash(
            (
                self.vfp_id,
                self.project_name,
                tuple(self.findings),
                tuple(self.affected_files),
            )
        )
