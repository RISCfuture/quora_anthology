class Answer < Struct.new(:title, :description, :answer, :upvotes, :date, :topics,
  :permalink)

  def to_json(*args)
    {
        title:       title.try!(:to_html),
        description: description.try!(:to_html),
        answer:      answer.try!(:to_html),
        upvotes:     upvotes,
        date:        date,
        topics:      topics,
        permalink:   permalink
    }.to_json(*args)
  end

  def self.from_json(hsh)
    new hsh['title'],
        hsh['description'],
        hsh['answer'],
        hsh['upvotes'],
        Date.strptime(hsh['date'], '%Y-%m-%d'),
        hsh['topics'],
        hsh['permalink']
  end
end

COMMON_HEADERS = {
    'Pragma'        => 'no-cache',
    'DNT'           => '1',
    'Accept'        => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'User-Agent'    => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_3) AppleWebKit/601.4.4 (KHTML, like Gecko) Version/9.0.3 Safari/601.4.4',
    'Cache-Control' => 'max-age=0'
}

module Enumerable
  def mode
    return nil if empty?
    group_by(&:itself).values.max_by(&:size).first
  end
end
