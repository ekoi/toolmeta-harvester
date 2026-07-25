import logging
import re

import requests

from toolmeta_harvester.config import settings
from toolmeta_harvester.tasks import galaxy_workflow as ga_workflow
from toolmeta_harvester.tasks import galaxy_workflow_hub as gwh

logger = logging.getLogger(__name__)

BIOBB_WORKFLOWS_URL = settings.get(
    "biobb.workflows_url", "https://mmb.irbbarcelona.org/biobb/workflows"
)

# Capture canonical WorkflowHub workflow pages and ignore ro_crate/download links.
WORKFLOWHUB_URL_RE = re.compile(r"https?://workflowhub\.eu/workflows/(\d+)")


def fetch_workflows_page(url):
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return response.text


def extract_workflow_urls(page_html):
    seen = set()
    urls = []
    for workflow_id in WORKFLOWHUB_URL_RE.findall(page_html):
        wf_url = f"https://workflowhub.eu/workflows/{workflow_id}"
        if wf_url in seen:
            continue
        seen.add(wf_url)
        urls.append(wf_url)
    return urls


def get_latest_version_id(workflow_json):
    attrs = workflow_json.get("data", {}).get("attributes", {})
    latest = attrs.get("latest_version")
    if latest is not None:
        return str(latest)

    versions = attrs.get("versions", [])
    if not versions:
        return None

    return str(versions[-1].get("version") or "") or None


def iter_workflows(workflows_url=None):
    source_url = workflows_url or BIOBB_WORKFLOWS_URL
    page_html = fetch_workflows_page(source_url)
    workflow_urls = extract_workflow_urls(page_html)
    logger.info(
        "Found %s workflowhub workflow URLs in BIOBB list: %s",
        len(workflow_urls),
        source_url,
    )

    for workflow_url in workflow_urls:
        try:
            wf_json = gwh.fetch_workflowhub_json(workflow_url)
            version_id = get_latest_version_id(wf_json)
            if not version_id:
                logger.warning("Missing latest version id for %s, skipping", workflow_url)
                continue

            ga_workflow_json = gwh.extract_galaxy_workflow_from_zip(
                f"{workflow_url}/ro_crate?version={version_id}"
            )
            workflow_info = ga_workflow.parse_workflow(ga_workflow_json)

            attrs = wf_json.get("data", {}).get("attributes", {})
            tags = list(attrs.get("tags") or [])
            if "biobb" not in tags:
                tags.append("biobb")
            if "jupyter" not in tags:
                tags.append("jupyter")

            workflow_info.url = workflow_url
            workflow_info.description = attrs.get("description", "")
            workflow_info.version = str(attrs.get("latest_version") or attrs.get("version") or "")
            workflow_info.tags = tags
            workflow_info.types = ["galaxy_workflow", "workflowhub", "biobb", "jupyter"]
            workflow_info.license = attrs.get("license") or ""
            workflow_info.raw_ga = ga_workflow_json
            workflow_info.raw_metadata = wf_json
            workflow_info.metadata_type = "workflowhub"
            workflow_info.metadata_version = wf_json.get("jsonapi", {}).get("version", "unknown")
            yield workflow_info

        except Exception as e:
            logger.error("Error processing BIOBB workflow %s: %s", workflow_url, e)
            continue

