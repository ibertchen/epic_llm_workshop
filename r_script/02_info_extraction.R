here::i_am("r_script/02_info_extraction.R")

require(dplyr)
require(stringr)
require(openxlsx)
require(ellmer)
require(here)

# load raw data
df <- read.xlsx(here("data/info_extract_sample.xlsx"))
df <- df |> 
  mutate(job_desc2 = paste0(
    "job title: ", 
    job_title, 
    "job description: ", 
    job_desc
  ))

# keep the first five rows
df <- head(df, 5)

# Set up LLM parameters ==== 
system_instruct <- readLines(here("materials/data_extraction_step1.md"))
system_instruct <- paste0(system_instruct, collapse = "\n")

extract_instruct <- r"(
  Please read this job posting: 
  
  "{{job}}"
  
  Find and extract information using the provided list of variables and definitions. 
  All the return values should be strings, including empty strings if no related 
  content is found in the job posting.
  )"

chat <- chat_openai(
  model = "gpt-4o-mini", 
  system_prompt = system_instruct
  )

# the batch API accepts data in list format
job <- df$job_desc2

prompts <- interpolate(extract_instruct)
prompts <- as.list(prompts)  

# This is the first step of data extraction, so 
# all data type are set to string to fit all possible extracted content
data_type <- type_object(
  posting_date = type_string(), 
  closing_date = type_string(),
  open_position = type_string(),
  attachments = type_string(), 
  job_location = type_string(), 
  subject_broad = type_string(), 
  school_level = type_string(), 
  grade = type_string(), 
  job_start = type_string(), 
  job_term = type_string(),
  ft_status = type_string(), 
  qual_cert = type_string(), 
  qual_endorse = type_string(),
  qual_language = type_string(),
  qual_softskills = type_string(),
  qual_experience = type_string(),
  qual_additional = type_string(), 
  compensation = type_string(), 
  job_persk = type_string()
  )

data_output <- batch_chat_structured(
    chat = chat, 
    prompts = prompts, 
    type = data_type, 
    path = "my_test_0.json"
)

# Check if the task is completed
batch_chat_completed(
    chat = chat, 
    prompts = prompts, 
    path = "my_test_0.json"
)

# Check current progress if the task is not done yet
# If the task is completed, it will return the details 
batch_chat(
    chat = chat, 
    prompts = prompts, 
    path = "my_test_0.json"
)

df <- cbind(df, data_output)

df <- df |> 
  select(-job_desc2)

write.xlsx(df, here("data/extract_output.xlsx"))

