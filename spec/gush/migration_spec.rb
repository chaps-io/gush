require 'spec_helper'

describe Gush::Migration do

  describe "#migrate" do
    it "applies a migration once" do
      class TestMigration < Gush::Migration
        def self.version
          123
        end
      end

      migration = TestMigration.new
      expect(migration).to receive(:up).once

      expect(migration.migrated?).to be(false)
      migration.migrate

      expect(migration.migrated?).to be(true)
      migration.migrate
    end
  end
end
