# Gush

Gush is a parallel workflow runner using only Redis as its message broker and Sidekiq for workers.

## Installation

Add this line to your application's Gemfile:

    gem 'gush'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install gush

## Usage

### Start workers

```ruby
sidekiq -r ./workflows/workflows.rb
```

### Start server

```ruby
gush server
```

## Contributing

1. Fork it ( http://github.com/<my-github-username>/gush/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
