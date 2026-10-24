Cognitive status classification using OASIS-1 data

Proposed mini-project title: Cognitive Status Classification Using OASIS-1 Clinical and MRI Measures

Students: Atharv Jaiswal (PRN 23070521023) and Shreya Bansal (PRN 23070521144)
Healthcare Analytics mentors: Dr. Bhupesh and Dr. Prerna
Institute: Symbiosis Institute of Technology, Nagpur

Project question
Among records with an observed Clinical Dementia Rating (CDR), can demographic information and MRI-derived measures distinguish records with CDR = 0 from records with CDR > 0? Does adding MRI and contemporaneous MMSE information change test performance compared with a demographic-only baseline?

The target is a recorded CDR grouping in a cross-sectional dataset. It is not a future outcome, a diagnosis, or an individual care recommendation.

Proposed analytical contribution
The analysis compares staged feature blocks (demographics, demographics plus MRI measures, then MMSE), several classifiers, and a soft-voting ensemble. Each candidate threshold is selected on validation data using F2, then evaluated on a separate test partition. The dataset contains one known-CDR row per participant, so the stratified split keeps participant IDs separate across partitions. This is a course-project analytical design, not a claim of a new clinical method.

Important data and course checks
The supplied workbook contains 436 rows and 12 columns. CDR is missing in 201 rows. Those rows are excluded because a missing target must not be invented.
The remaining 235 rows contain 135 CDR = 0 records and 100 CDR > 0 records. SES is missing in 19 eligible rows and is imputed from training data only.
The workbook was attached by the student in this chat. Confirm that this exact file is the dataset distributed by Dr. Prerna on Moodle before submission. Do not submit with it if it is not the approved course dataset.
The assignment requires student-written, AI-free report text. The editable report is a working scaffold with factual outputs and writing prompts. Replace prompts with your own explanation, run and explain the code yourself, and follow your instructor's policy for AI-assisted work.
Proposed project title for the course form: Cognitive Status Classification Using OASIS-1 Clinical and MRI Measures. The form has not been submitted.

#Run the project

From this folder, with R 4.3.2 and Python 3.12 installed:

python prepare_dataset.py
Rscript analysis.R
The R script uses base R and rpart 4.1.21. The Python workbook converter uses openpyxl 3.1.5. The split seed is 20261010. Analysis outputs are written to outputs/ and plots to outputs/plots/.

Package contents
data/oasis_cross-sectional-5708aa0a98d82080.xlsx - workbook supplied by the student.
data/oasis_cross-sectional.csv - CSV created from the workbook sheet.
prepare_dataset.py - reproducible XLSX-to-CSV conversion.
analysis.R - preprocessing, stratified split, models, thresholds, metrics and charts.
outputs/ - audit, attribute dictionary, split details, predictions, coefficients, metrics and figures.
report/Healthcare_Analytics_Report_Working_Draft.docx - editable report scaffold with prompts for student-authored text.
presentation/Healthcare_Analytics_Project_Presentation.pptx - editable presentation with factual results and student explanation prompts.

Data source citation

Marcus, D. S., Wang, T. H., Parker, J., Csernansky, J. G., Morris, J. C., and Buckner, R. L. (2007). Open Access Series of Imaging Studies (OASIS): Cross-sectional MRI data in young, middle-aged, nondemented, and demented older adults. Journal of Cognitive Neuroscience, 19(9), 1498-1507. https://doi.org/10.1162/jocn.2007.19.9.1498

Official OASIS source: https://sites.wustl.edu/oasisbrains/
