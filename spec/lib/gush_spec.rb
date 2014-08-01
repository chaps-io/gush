require 'spec_helper'

describe Gush do
  describe ".gushfile" do
    context "Gushfile.rb is missing from pwd" do
      it "raises an exception" do
        path = Pathname("/tmp/Gushfile.rb")
        path.delete if path.exist?

        allow(Pathname).to receive(:pwd).and_return(Pathname("/tmp"))

        expect { Gush.gushfile }.to raise_error(Thor::Error)
      end
    end

    context "Gushfile.rb exists" do
      it "returns Pathname to it" do
        path = Pathname.new("/tmp/Gushfile.rb")
        FileUtils.touch(path)
        allow(Pathname).to receive(:pwd)
          .and_return(Pathname.new("/tmp"))
        expect(Gush.gushfile).to eq(path)
        path.delete
      end
    end
  end

  describe ".root" do
    it "returns root directory of Gush" do
      expected = Pathname.new(__FILE__).parent.parent.parent
      expect(Gush.root).to eq(expected)
    end
  end

  describe ".configure" do
    it "runs block with config instance passed" do
      expect { |b| Gush.configure(&b) }.to yield_with_args(Gush.configuration)
    end
  end

end
