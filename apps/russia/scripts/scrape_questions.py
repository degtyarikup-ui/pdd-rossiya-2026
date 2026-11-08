import requests
import json
import re
import time
from bs4 import BeautifulSoup

BASE_URL = "https://examenpdd.com"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

def fetch_ticket_page(ticket_num):
    url = f"{BASE_URL}/tickets/{ticket_num}"
    resp = requests.get(url, headers=HEADERS, timeout=15)
    resp.raise_for_status()
    return resp.text

def parse_ticket_questions(html, ticket_num):
    soup = BeautifulSoup(html, "html.parser")
    questions = []
    
    # Find all question blocks
    question_blocks = soup.find_all("div", class_=re.compile(r"ticket-question|question", re.I))
    
    if not question_blocks:
        # Try alternative selectors
        question_blocks = soup.find_all("div", {"data-question": True})
    
    if not question_blocks:
        # Try finding by ordered list items
        ol = soup.find("ol")
        if ol:
            items = ol.find_all("li")
            for i, item in enumerate(items, 1):
                q_text = item.get_text(strip=True)
                # Extract just the question text (remove number prefix)
                q_text = re.sub(r'^\d+\.\s*', '', q_text)
                questions.append({
                    "id": f"{ticket_num}_{i}",
                    "question": q_text,
                    "answers": [],
                    "comment": "",
                    "pddPoints": [],
                    "image": None
                })
    
    return questions

def fetch_question_detail(ticket_num, q_num):
    """Try to fetch individual question detail page"""
    urls_to_try = [
        f"{BASE_URL}/tickets/{ticket_num}/{q_num}",
        f"{BASE_URL}/tickets/{ticket_num}/question/{q_num}",
        f"{BASE_URL}/ticket/{ticket_num}/{q_num}",
    ]
    
    for url in urls_to_try:
        try:
            resp = requests.get(url, headers=HEADERS, timeout=10)
            if resp.status_code == 200:
                return resp.text
        except:
            continue
    return None

def parse_question_detail(html):
    if not html:
        return None
    
    soup = BeautifulSoup(html, "html.parser")
    
    # Try to find question text
    question_el = soup.find("h1") or soup.find("h2") or soup.find("div", class_=re.compile(r"question", re.I))
    question_text = question_el.get_text(strip=True) if question_el else ""
    
    # Try to find answers
    answers = []
    answer_els = soup.find_all("label") or soup.find_all("div", class_=re.compile(r"answer", re.I))
    for el in answer_els:
        text = el.get_text(strip=True)
        if text:
            answers.append({"text": text, "correct": False})
    
    # Try to find comment/explanation
    comment_el = soup.find("div", class_=re.compile(r"comment|explanation|hint", re.I))
    comment = comment_el.get_text(strip=True) if comment_el else ""
    
    return {
        "question": question_text,
        "answers": answers,
        "comment": comment
    }

def main():
    all_tickets = []
    
    for ticket_num in range(1, 41):
        print(f"Scraping ticket {ticket_num}/40...")
        try:
            html = fetch_ticket_page(ticket_num)
            questions = parse_ticket_questions(html, ticket_num)
            
            if questions:
                # Try to get details for each question
                for i, q in enumerate(questions):
                    q_num = i + 1
                    print(f"  Question {q_num}/20...")
                    detail_html = fetch_question_detail(ticket_num, q_num)
                    if detail_html:
                        detail = parse_question_detail(detail_html)
                        if detail:
                            if detail["question"]:
                                q["question"] = detail["question"]
                            if detail["answers"]:
                                q["answers"] = detail["answers"]
                            if detail["comment"]:
                                q["comment"] = detail["comment"]
                    time.sleep(0.5)
                
                all_tickets.append({
                    "number": ticket_num,
                    "questions": questions
                })
                print(f"  Got {len(questions)} questions")
            else:
                print(f"  No questions found for ticket {ticket_num}")
            
            time.sleep(1)
            
        except Exception as e:
            print(f"  Error: {e}")
            continue
    
    result = {"tickets": all_tickets}
    
    with open("/Users/sergei/Documents/pdd/assets/questions/questions_ab.json", "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    
    total_questions = sum(len(t["questions"]) for t in all_tickets)
    print(f"\nDone! Saved {total_questions} questions from {len(all_tickets)} tickets")

if __name__ == "__main__":
    main()
