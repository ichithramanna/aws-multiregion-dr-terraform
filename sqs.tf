# ─── SQS Write Buffer Queue (DR region) ──────────────────────────
# Purpose: during Aurora Global DB failover, the DR secondary is
# temporarily READ-ONLY (~60-90s while promotion completes).
# Writes that hit errno 1290 are sent here instead of failing.
# The drain worker in app.py polls this queue and flushes writes
# to Aurora once it becomes writable after promotion.
#
# Why us-west-2 (DR region)?
# Because this queue is only used by DR EC2s during failover.
# Keeping it in the same region as the DR EC2 avoids cross-region
# SQS latency and keeps IAM permissions simple.

resource "aws_sqs_queue" "dr_write_buffer" {
  provider = aws.dr # us-west-2 — same region as DR EC2
  name     = "dr-write-buffer"

  # visibility_timeout must be LONGER than your drain retry window
  # drain worker retries every 5s, Aurora promotion takes ~75s
  # 120s gives enough headroom before SQS re-delivers the message
  visibility_timeout_seconds = 120

  # keep messages for 1 hour max — if not flushed by then, discard
  # in a real production system you'd set this much higher + add DLQ
  message_retention_seconds = 3600

  tags = { Name = "dr-write-buffer" }
}

output "dr_write_buffer_url" {
  value       = aws_sqs_queue.dr_write_buffer.url
  description = "Passed to DR EC2 docker run as SQS_QUEUE_URL env var"
}
