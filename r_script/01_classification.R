pkgs <- c(
  "dplyr", 
  "stringr", 
  "ellmer",
  "openxlsx",
  "here",
  "usethis", 
  "purrr"
)

for (i in pkgs) {
  install.packages(i, type = "binary")
}

here::i_am("r_script/01_classification.R")

purrr::walk(pkgs, library, character.only = TRUE)
rm(pkgs, i)

# set API key
# edit_r_environ()


# Load and prepare sample data ==== 
df <- read.xlsx(here("data/tch_classification_1.xlsx"))


# Combine job_title and job_description
df <- df |> 
  mutate(job_desc2 = paste0(
    "job_title: ", 
    job_title, 
    "\n", 
    "job description:", 
    job_desc
  ))

cat(pull(df, job_desc2)[11])


# Set up LLM parameters ==== 
## create system role instruction: what role the LLM should play ---- 
### method 1: edit locally ---- 
system_instruct <- r"(
  You are a K-12 education expert familiar with different job positions in K-12 
  schools. You will be provided a job posting, and your task is to classify the 
  job into a pre-defined category based on the job title and description. 

  --- 
  
  There are three job categories, and the corresponding definitions are described below.

  **Type 1: K-12 classroom teacher**
    A conventional teacher role that meets ALL the following criteria:
      - The position teaches students from kindergarten to 12th grade, or 6 to 18
        years old, including elementary, middle, and high school students
      - The position teaches a specific subject in K-12 education
      - The position teaches during regular school hours, excluding summer and 
        after-school hours
      - The position can be either full-time or part-time

    The job title of this type may include the word "teacher" or not, such as 
    "secondary science teacher" or "math 6-12 grades."

  **Type 2: Other teaching position**
    A teaching-related position, but not a K-12 classroom teacher. A job is
    recognized as this type if it meets any of the following criteria:
      - The position is for early childhood, preschool/pre-kindergarten, adult, 
        or continuing education, including Great Start Readiness Program (gsrp),
        early childhood special education (ecse), and those who teach students 
        over 18 years old
      - The position teaches students outside the regular K-12 school hours, 
        such as summer school teachers or after-school teachers
      - The position teaches students outside the K-12 schools, such as a homebound 
        teacher
      - The position is a substitute, sub or guest teacher, either long-term or 
        short-term, such as "long-term sub English teacher," "short-term Math 
        sub teacher"
      - The position is a "remote teacher," "online teacher," or "virtual teacher" 
        who is equipped with teaching license or certificate
      - The position is an "intervention teacher,""support teacher," 
        "instructional coach," "teacher consultant," "academic advisor," or 
        "academic specialist" 

  **Type 3: Non-teaching position**
    A position that is not included in the first two types and meets any of the following criteria:
      - A job title containing any of the following keywords: "teacher assistant," 
        "associate teacher," "assistant teacher," "classroom aide," "paraprofessional," 
        "paraeducator," "pathologist," "therapist," "navigator," or "social worker," 
        regardless of the job description
      - An instructor, tutor, interventionist, mentor, or specialist WITHOUT a 
        teaching license or certificates requirement
      - A sports coach
      - "Superintendent," "supervisor," "student support service," 
        "sponsor," "liaison," "coordinator," or other administrative role
      - Any other position not involved in teaching activities

  --- 
  
  Pay attention to the following rules when you make a job classification: 
    - Do not simply recognize a job position as a Type 1 K-12 classroom 
      teacher merely because there is a description of "type: teacher" in the 
      job description
    - Do not simply recognize a job position as a Type 2 Other teaching position 
      merely because the position works for a summer program or summer school. 
      For example, a "summer program coordinator" or "summer liaison" job is a Type 3 
    - A music band director is a Type 1 K-12 classroom teacher
    - A resource room teacher is a Type 1 K-12 classroom teacher, excluding 
      early childhood, preschool and adult education
    - A summer school or summer program teacher ISN'T be a Type 1 K-12 classroom teacher.
    - If it is a teacher position and the job title contains "sub," "substitute," 
      or "temporary," classifying it a Type 2 Other teaching position
    - If it is a intervention teacher, instructional coach, or teacher consultant who 
      works on a specific subject, such as "English intervention teacher," 
      "literacy coach," or "special education teacher consultant," it is a 
      Type 2 Other teaching position
    - A job title containing "assistant teacher" or "associate teacher" is a 
      Type 3 Non-teaching position, regardless of the job description
    - If the position is self-taught, it is a Type 3 Non-teaching position

  --- 

  If a job's classification is ambiguous, you can prioritize Type 3, then Type 2, 
  and Type 1 as the last option. 

  --- 

  You must use the provided job categories and definitions to classify a job 
  posting. Ensure you have reviewed all the options and criteria before making 
  a classification.
)"

### method 2: import from a markdown file ---- 
system_instruct <- readLines(here("materials/tch_classification.md"), encoding = "UTF-8")
system_instruct <- paste(system_instruct, collapse = "\n")


## create behavior instruction ---- 
classify_instruct <- r"(
  Please read this job posting: 
  
  "{{job}}"
  
  Classify the job into one of the pre-defined job categories. 
  Return the job category's number (i.e., 1, 2, or 3) and no other commentary.
)"


# Classify job position using LLM via API ==== 
## Here we use real-time API
classify_output <- as.character()

row = 1

for (i in df$job_desc2) {    
  # progress check
  if (row %% 50 == 0) {
    print(row)
  }
  
  # interpolating data into the prompt
  job_instruct <- interpolate(classify_instruct, job = i)
  
  # set up chatbot
  chat <- chat_openai(
    system_prompt = system_instruct, 
    model = "gpt-4o-mini", 
    params = list(temperature = 0.1)  # lower value reduces output variation
  )
  
    chat_output <- chat$chat(job_instruct, echo = "none")
  
  classify_output <- c(classify_output, chat_output)

  row = row + 1
}


# QUIZ: Why set up the chatbot inside the loop?  ==== 
# What would happen if we do this: 
chat <- chat_openai(
  system_prompt = system_instruct, 
  model = "gpt-4o-mini", 
  params = list(temperature = 0.1)
) 

for (i in df$job_desc2) {
  if (row %% 50 == 0) {
    print(row)
  }

  job_instruct <- interpolate(classify_instruct, job = i)

  chat_output <- chat$chat(job_instruct, echo = "none")

  classify_output <- c(classify_output, chat_output)

  row = row + 1
}


# Merge the classification output back to the original data ==== 

df <- df |> 
  mutate(is_tch_llm = as.integer(classify_output)) |> 
  relocate(is_tch_llm, .after = is_tch)

# flag is_tch != is_tch_llm
df <- df |> 
  mutate(flag = if_else(is_tch!=is_tch_llm, 1, 0)) |> 
  relocate(flag, .after = is_tch_llm)

# Any inconsistent results? 
## We tested on 5 subsets (1500 different job postings), and
## the classification accuracy rate is between 95% ~ 100% 
df |> count(flag)

df <- df |> 
  select(-job_desc2)

write.xlsx(df, here("data/tch_classification_1_parsed.xlsx"))


