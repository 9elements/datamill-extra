module Datamill
  module Extra

# Manages asynchronous jobs with an identifier (`work_id`).
# Cannot be used concurrently per work_id.
class IdentifiedAsyncWork

  def initialize(thread_pool)
    @thread_pool = thread_pool
    @work_ids = []
    @load = Proc.new
  end

  def running?(work_id)
    @work_ids.include?(work_id)
  end

  def run_asynchronously(work_id, args)
    @work_ids << work_id

    @thread_pool.post do
      @load.call(args)
      @work_ids.delete work_id
    end
  end
end

  end
end
