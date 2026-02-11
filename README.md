# FORGE Curated: A Curated EVM Smart Contracts Vulnerability Dataset

**FORGE Curated** is a high-quality subset of the [FORGE dataset](https://github.com/shenyimings/FORGE-Artifacts), specifically designed to support advanced research in smart contract security, AI-based auditing, and vulnerability analysis.

Building upon feedback from users of the original FORGE Dataset and fulfilling our commitment to responsible updates outlined in our [ICSE'26 paper]("https://arxiv.org/abs/2506.18795"), we have compiled a new collection of audit reports. This dataset includes reports published between **December 2024 and February 2026** by **11 top-tier audit teams**.

Using the [FORGE tool](https://github.com/shenyimings/FORGE-Artifacts/tree/main/src), we classified vulnerability data from these reports and organized them into the [dataset-curated](dataset-curated) directory. We are conducting **manual verification** process to ensure accurate mapping between vulnerability findings and specific code locations.

We plan to continuously maintain and update this directory to support the community's research and development efforts.

## Structure

The repository is organized as follows:

```text
FORGE-Curated/
├── dataset-curated/            # Core curated dataset
│   ├── contracts/              # Source code associated with reports
│   ├── contracts-raw/          # Raw contract data
│   ├── findings/               # Extracted vulnerability findings (JSON)
│   ├── findings-without-source/# Findings where source code could not be resolved
│   └── reports/                # Original PDF audit reports
├── flatten/                    # Flattened datasets with findings and source code in single files
│   ├── vfp/                    # Vulnerability-File Pairs (All)
│   └── vfp-vuln/               # Vulnerability-File Pairs (Higher severity only)
├── LICENSE
├── models/                     # Data models and definitions
│   ├── cwe_dict.json           # CWE dictionary
│   └── schemas.py              # Pydantic data schemas
├── README.md
└── scripts/                    # Utility scripts
    ├── process.ipynb           # Data processing
    └── statistic.ipynb         # Statistical analysis

```

## Examples

### Vulnerability Finding (JSON)

```json
{
    "path": "dataset-curated/reports/TrailofBits/2024-12-balancer-v3-securityreview.pdf",
    "project_info": {
        "url": ["https://github.com/balancer/balancer-v3-monorepo"],
        "commit_id": ["a24ebf0141e9350a42639d8593c1436241deae59"],
        "audit_date": "2024-08-05",
        "chain": "ethereum"
    },
    "findings": [
        {
            "id": 0,
            "category": {"1": ["CWE-284"], "2": ["CWE-285"], "3": ["CWE-862"]},
            "title": "Lack of approval reset on buffer allows anyone to drain the Vault",
            "description": "The lack of approval reset after the call to deposit allows a malicious wrapper contract to steal the Vault's funds...",
            "severity": "High",
            "location": [
                "Vault.sol::deposit#1169-1172",
                "Vault.sol::erc4626BufferWrapOrUnwrap"
            ],
            "files": [
                "balancer-v3-monorepo/pkg/vault/contracts/Vault.sol"
            ]
        },
        ......
    ]
}

```

### Vulnerability-File Pair (VFP)

```json
{
    "vfp_id": "vfp_00016",
    "project_name": "cantina_uniswap_april2025.pdf",
    "findings": [
        {
            "id": 0,
            "category": {"1": ["CWE-284"], "2": ["CWE-285"], "3": ["CWE-863"]},
            "title": "Execute calls can be front-run",
            "description": "The `execute` function in the MinimalDelegation contract is publicly callable...",
            "severity": "High",
            "location": ["MinimalDelegation.sol::execute#66"],
            "files": ["minimal-delegation/src/MinimalDelegation.sol"]
        },
        ......
    ],
    "affected_files": {
        "MinimalDelegation.sol": "// SPDX-License-Identifier: UNLICENSED\npragma solidity ^0.8.29;\n\nimport {EnumerableSetLib}...",
        ......
    }
}

```


## Statistics

### General Overview

| Metric | Value |
| --- | --- |
| **Total Projects** | 249 |
| **Valid Projects** | 249 |
| **Total Files Analyzed** | 209 |
| **Total Findings** | 2,556 |
| **Total Solidity Files** | 28,925 |
| **Total Lines of Code (LoC)** | 4,724,389 |
| **Avg. LoC per Project** | ~18,973 |
| **Avg. Files per Project** | ~116 |

### Findings by Severity

| Severity Level | Count |
| --- | --- |
| **Critical** | 68 |
| **High** | 254 |
| **Medium** | 439 |
| **Low** | 794 |
| **Informational** | 908 |
| **N/A** | 93 |

### Dataset Composition

| Metric | Value |
| --- | --- |
| **Total Vulnerability-File Pairs (VFPs)** | 660 |
| **High-Impact VFPs (Medium/High/Critical)** | 322 |

> Note: many to-many relationship between findings and files, so the number of VFPs is less than total findings


## Data Schema

The data follows a strict schema defined in [models/schemas.py](models/schemas.py). Below is the standard definition for the core objects.

### Finding from Audit Reports

JSON files in [dataset-curated/findings](dataset-curated/findings) and [dataset-curated/findings-without-source](dataset-curated/findings-without-source) directories follow this structure:


| Field | Type | Description |
| --- | --- | --- |
| `path` | `str` | Path to the original audit report PDF. |
| `project_info` | `ProjectInfo` |  Metadata regarding the audited project. |
| `findings` | `List[Finding]` |  List of vulnerability findings in the report. |


`ProjectInfo`: Metadata regarding the audited project.

| Field | Type | Description |
| --- | --- | --- |
| `url` | `Union[str, List]` | URL(s) to the project repository. |
| `commit_id` | `Union[str, List]` | The specific commit hash audited. |
| `chain` | `str` | The blockchain network (e.g., Ethereum). |
| `audit_date` | `str` | Date of the audit report. |
| `project_path` | `Dict` | Mapping of project names to local storage paths. |


`Finding`: Represents a single vulnerability found in an audit report.

| Field | Type | Description |
| --- | --- | --- |
| `id` | `Union[str, int]` | Unique identifier for the finding within the report. |
| `category` | `Dict` | Mapping of the vulnerability to CWE categories following a tree structure (e.g., `{"1": ["CWE-284"]}`). |
| `title` | `str` | The title of the finding as stated in the report. |
| `description` | `str` | Detailed description of the vulnerability. |
| `severity` | `Union[str, List]` | Severity level (e.g., High, Medium, Low, Critical). |
| `location` | `Union[str, List]` | Precise location in the code extracted by LLM, usually following a format like `filename.sol::function#line`. |
| `files` | `List[str]` | List of files affected by this finding. |



### Vulnerability-File Pair (VFP)

JSON files in the [flatten/vfp](flatten/vfp) and [flatten/vfp-vuln](flatten/vfp-vuln) directories follow this structure:

| Field | Type | Description |
| --- | --- | --- |
| `vfp_id` | `str` | Unique ID for the pair (e.g., `vfp_00016`). |
| `project_name` | `str` | Name of the source audit report/project. |
| `findings` | `List[Finding]` | List of findings contained in this VFP. |
| `affected_files` | `Dict[str, str]` | Dictionary where Key is filename and Value is the full source code string. |

<details>
<summary><strong>View Pydantic Data Model Code</strong></summary>

```python
@dataclass
class ProjectInfo:
    url: Union[str, int, List, None] = "n/a"
    commit_id: Union[str, int, List, None] = "n/a"
    address: Union[str, List, None] = field(default_factory=lambda: "n/a")
    chain: Union[str, int, List, None] = "n/a"
    compiler_version: Union[str, List, None] = "n/a"
    audit_date: str = "n/a"
    project_path: Union[str, Dict, None] = "n/a"

@dataclass
class Finding:
    id: Union[str, int] = 0
    category: Dict = field(default_factory=dict)
    title: str = ""
    description: str = ""
    severity: Union[str, List, None] = field(default_factory=lambda: "")
    location: Union[str, List, None] = field(default_factory=lambda: "")
    files: Union[str, List, None] = field(default_factory=list)

class Report(BaseModel):
    path: str = ""
    project_info: ProjectInfo = field(default_factory=ProjectInfo)
    findings: List[Finding] = field(default_factory=list)

class VulnerabilityFilePair(BaseModel):
    vfp_id: str = "" 
    project_name: str = ""
    findings: List[Finding] = Field(default_factory=list)
    affected_files: Dict[str, str] = Field(default_factory=dict)

```

</details>


## Important Notes

* **Commit Checkout:** The submodules in this repository are not automatically checked out to the audited commit. To work with the specific version of the code that was audited, you must manually (or use the Git python module) `checkout` the `commit_id` provided in the project's metadata.
* For some projects, the commit ID referenced in the audit report is no longer part of the main repository tree. While these commits are still accessible on GitHub, they have been manually downloaded for this dataset and therefore do not contain `.git` metadata.
* In rare cases where the exact commit ID from the audit was deleted or unavailable, we have selected the nearest available commit preceding it.
* **Disclaimer:** All data is collected from public sources. The inclusion of an audit team in this list is based on preliminary collection and does not constitute a ranking of audit quality. Furthermore, it does not guarantee that the projects are free of bugs. We plan to gradually include more audit teams and encourage community-driven contributions.

## FAQ

### Q: How does FORGE Curated differ from the original FORGE dataset?

**A:** FORGE Curated focuses on new, high-quality audit reports published between **Dec 2024 and Feb 2026** from 11 premium audit teams. We are applying **manual verification** (ongoing) to match vulnerabilities with their exact file locations more accurately.
Additionally, to facilitate LLM training and evaluation, we provide a **flattened VFP dataset**. This constructs "Vulnerability-File Pairs" where the `.sol` source code and the vulnerability description coexist in a single `.json` file, simplifying data loading.

### Q: Why use CWE for vulnerability classification?

**A:** The Web3 ecosystem lacks a comprehensive, scientifically hierarchical vulnerability taxonomy. Existing standards like SWC, DASP10, or OWASP SCWE are often outdated, not comprehensive enough, or lack widespread adoption.
We utilize **CWE (Common Weakness Enumeration)** because it is a globally recognized software vulnerability classification system. It provides a unified standard for description and classification, facilitating comparison between different tools and research. Using CWE enhances the dataset's usability and universality.

### Q: How can I use the FORGE Curated dataset?

**A:** The dataset is suitable for various scenarios:

* **Benchmarking & Training:** For AI-based smart contract auditing systems.
* **Tool Evaluation:** Assessing SAST/DAST vulnerability analysis tools.
* **Education:** Learning and practicing Web3 security.
* **Ecosystem Analysis:** Analyzing smart contract security trends from late 2024 to early 2026.

Refer to the [scripts/](scripts/) directory for examples on how to load and process the data.

### Q: How should I evaluate using CWE types?

**A:** Due to the large scale and complexity of the CWE hierarchy, we suggest different evaluation methods based on your goal:

* **For SAST/DAST Evaluation:** Map the tool's output to CWE root causes manually (or via official guides). If the detected CWE exists in the Ground Truth CWE tree, count it as a True Positive (TP).
* **For LLM Evaluation:**
  * **Binary/Multi-class:** Ask the LLM to identify if a specific CWE exists in the affected files or list all possible CWEs.
  * **LLM-as-a-Judge:** Given the rich context (Title/Description/Location) in our dataset, you can ignore strict CWE matching and use another LLM to judge if your system "caught the point."
* **Tools:** We plan to develop automated evaluation tools. In the meantime, you can look at third-party alternatives like [scabench](https://github.com/scabench-org/scabench) or [auditagent-scoring-algo](https://github.com/NethermindEth/auditagent-scoring-algo).



### Q: How can I focus only on exploitable vulnerabilities (ignoring code quality/Gas optimization)?

**A:** You can filter by the **Severity** field or specific **CWE types**.

* *Note:* While categories like `CWE-710` (Code Quality) often contain non-exploitable issues (e.g., `CWE-1041`, `CWE-1164`), some sub-types like `CWE-657` (Violation of Secure Design Principles) can be high-severity. Always cross-reference with the finding title and description.
* We provide a filtered example in the `flatten/vfp-vuln` directory, which retains only vulnerabilities with **Medium** severity and above(Medium, High, and Critical).

### Q: Are there similar datasets for other ecosystems?

**A:** Yes, stay tuned!

### Q: I want to contribute to FORGE Curated. How?

**A:** We welcome community contributions via Issues and PRs.

* **Fixes:** If you find errors in classification or location, open an Issue/PR indicating the Finding ID and the correct information. We will verify and merge these fixes regularly.
* **New Reports:** To submit new audit or bug bounty reports, please ensure the project code is open-source. Submit a PR adding the PDF to `dataset-curated/reports/<AuditorName>/`.
* **New Auditors:** If you want us to track a specific audit team, please open an Issue with their name, website, and a link to their public reports.