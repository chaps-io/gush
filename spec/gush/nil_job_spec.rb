require 'spec_helper'

describe Gush::NilJob do
  describe '#name' do
    it 'prepends "Removed - "' do
      job = described_class.from_hash(
        klass: 'Gush::RemovedJob',
        id: '702bced5-bb72-4bba-8f6f-15a3afa358bd'
      )

      expect(job.name).to eq('Removed - Gush::RemovedJob|702bced5-bb72-4bba-8f6f-15a3afa358bd')
    end
  end
end
