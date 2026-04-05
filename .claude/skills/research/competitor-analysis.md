---
name: competitor-analysis
description: Saul's standard framework for competitive analysis and market intelligence
version: 1.0.0
updated: 2026-04-05
updated_by: ray
---

## When to Use
Every research session. Run all four lenses.

## Lens 1: Competitor Features

For each direct competitor:
1. Check their changelog/blog for recent launches (last 30 days)
2. Check their pricing page — any changes?
3. Check their G2/Capterra reviews — what do customers complain about?
4. Check their job postings — what are they hiring for? (signals future direction)

**Good sources:**
- Product's own blog/changelog
- G2.com, Capterra, Trustpilot reviews
- LinkedIn job postings
- Hacker News ("Ask HN: alternatives to X")

## Lens 2: User Pain Points

Find real users complaining about the problem we solve:
1. Reddit: search `r/[relevant subreddits]` for complaints
2. Twitter/X: search "I wish [competitor] had" or "[problem] is so annoying"
3. ProductHunt: read comments on competitor listings
4. Slack communities in the target market

**Output format:**
```
Pain point: [exact user quote or paraphrase]
Source: [URL]
Frequency: [how many users mention this?]
Opportunity: [what we could build]
```

## Lens 3: SEO Opportunities

1. Identify 5-10 keywords competitors rank for that we don't
2. Check keyword difficulty + monthly volume (target: <50 difficulty, >500 vol)
3. Identify "vs" and "alternative" keywords (high intent)
4. Find featured snippet opportunities (questions we could answer)

**Tools:** Use web search to check SERPs for target keywords.

## Lens 4: Feature Gap Analysis

What are customers paying for that we don't offer?
1. Read 1-star reviews of competitors: "I wish it had..."
2. Check feature request boards (Canny, UserVoice) if public
3. Reddit: "does [competitor] have X?" threads
4. Check "compared to" sections on competitor landing pages

## Output

Create one task per actionable insight. Priority matrix:

| Impact | Effort | Priority |
|--------|--------|----------|
| High | Low | 🔴 High — do it now |
| High | High | 🟡 Medium — plan it |
| Low | Low | 🟢 Low — easy win |
| Low | High | ⬜ Skip |

## Pitfalls
- Don't track features that are hard to build without clear user demand
- Don't chase every competitor move — focus on what customers actually need
- Verify pain points from multiple sources before creating tasks

## Verification
Research session complete when: 3+ tasks created, summary posted to #forge-research.
