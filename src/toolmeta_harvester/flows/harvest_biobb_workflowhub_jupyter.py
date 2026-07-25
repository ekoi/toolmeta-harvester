import logging
from pathlib import Path
import sys

# Allow running this file directly without editable install.
if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from toolmeta_harvester.tasks import biobb_workflow_hub as bwh
from toolmeta_harvester.tasks import galaxy_harvest_tasks as ght

LOG_FILE = Path("logs/harvest_biobb_workflowhub_jupyter.log")
LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s: %(message)s",
    handlers=[logging.StreamHandler(), logging.FileHandler(LOG_FILE)],
)

logger = logging.getLogger(__name__)


def pipeline_harvest_biobb_jupyter_workflows(no_of_workflows=-1):
    ght.create_tables()
    session = ght.get_db_session()
    try:
        harvested = 0
        for workflow_info in bwh.iter_workflows():
            logger.info("Workflow URL: %s", workflow_info.url)
            logger.info("Name: %s", workflow_info.name)
            logger.info("Version: %s", workflow_info.version)
            logger.info("Tags: %s", ", ".join(workflow_info.tags))
            logger.info("Input formats: %s", workflow_info.input_formats)
            logger.info("Output formats: %s", workflow_info.output_formats)

            ght.add_workflow_to_generic_table(workflow_info, session)
            harvested += 1

            if no_of_workflows >= 0 and harvested >= no_of_workflows:
                break

        logger.info("Harvested %s BIOBB WorkflowHub workflows", harvested)
    finally:
        session.close()


def main():
    logger.info("Starting BIOBB WorkflowHub jupyter workflow harvesting process.")
    pipeline_harvest_biobb_jupyter_workflows(-1)


if __name__ == "__main__":
    main()

