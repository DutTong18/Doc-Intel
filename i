pip install pdfplumber

python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs
python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs --report misses.csv --recursive
python compare_cu_to_pdf.py ./my_pdfs ./cu_outputs --report misses.json --min-word-length 3



pip install requests
export CONTENTUNDERSTANDING_ENDPOINT="https://<your-resource>.cognitiveservices.azure.com"
export CONTENTUNDERSTANDING_KEY="<your-key>"

python batch_content_understanding.py ./my_pdfs ./cu_outputs
# or with a custom analyzer
python batch_content_understanding.py ./my_pdfs ./cu_outputs \
    --analyzer-id my-custom-analyzer --recursive --workers 8

