import unittest

from toolmeta_harvester.tasks import biobb_workflow_hub as bwh


class TestBiobbWorkflowHub(unittest.TestCase):
    def test_extract_workflow_urls_deduplicates_and_normalizes(self):
        html = """
        <a href=\"https://workflowhub.eu/workflows/120\">wf 120</a>
        <a href=\"https://workflowhub.eu/workflows/120/ro_crate\">wf 120 crate</a>
        <a href=\"https://workflowhub.eu/workflows/279\">wf 279</a>
        """

        urls = bwh.extract_workflow_urls(html)
        self.assertEqual(
            urls,
            [
                "https://workflowhub.eu/workflows/120",
                "https://workflowhub.eu/workflows/279",
            ],
        )

    def test_get_latest_version_id(self):
        metadata = {
            "data": {
                "attributes": {
                    "latest_version": 8,
                    "versions": [
                        {"version": 6},
                        {"version": 8},
                    ],
                }
            }
        }

        self.assertEqual(bwh.get_latest_version_id(metadata), "8")


if __name__ == "__main__":
    unittest.main()

