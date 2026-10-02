from pathlib import Path
import shutil

workflow = Path(".github/workflows/pandora-ux-regression.yml")
text = workflow.read_text()
text = text.replace("permissions:\n  contents: write", "permissions:\n  contents: read")
text = text.replace("          persist-credentials: true", "          persist-credentials: false")
text = text.replace(
    "      - name: Refresh reviewed Lane G goldens for artifact promotion",
    "      - name: Verify committed Lane E and Lane G goldens",
)
text = text.replace(
    '              --plain-name "captures $case_name" \\\n              --update-goldens',
    '              --plain-name "captures $case_name"',
)
text = text.replace(
    "          cp build/owner-screen-evidence/lane_g_bok_restaurants_section_390x844.png test/goldens/owner_screens/lane_g_bok_restaurants_section_390x844.png\n",
    "",
)
start = text.index("      # BEGIN LANE_G_PROMOTION\n")
end_marker = "      # END LANE_G_PROMOTION\n\n"
end = text.index(end_marker, start) + len(end_marker)
text = text[:start] + text[end:]
workflow.write_text(text)

src = Path("apps/pandora-mobile/build/owner-screen-evidence/lane_g_bok_restaurants_section_390x844.png")
dst = Path("apps/pandora-mobile/test/goldens/owner_screens/lane_g_bok_restaurants_section_390x844.png")
dst.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(src, dst)

Path(__file__).unlink()
