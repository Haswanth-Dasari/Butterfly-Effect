-- Add this after both tables exist because branch and event reference each other.
ALTER TABLE branch
    ADD CONSTRAINT branch_fork_event_fk FOREIGN KEY (fork_event) REFERENCES event(event_id);
