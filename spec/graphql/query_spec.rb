require 'spec_helper'

describe GraphQL::Query do
  let(:query_string) { "post(123) { title, content } "}
  let(:query) { GraphQL::Query.new(query_string, namespace: Nodes) }

  before do
    @post = Post.create(id: 123, content: "So many great things", title: "My great post")
    @comment1 = Comment.create(id: 444, post_id: 123, content: "I agree", rating: 5)
    @comment2 = Comment.create(id: 445, post_id: 123, content: "I disagree", rating: 1)
    @like1 = Like.create(id: 991, post_id: 123)
    @like2 = Like.create(id: 992, post_id: 123)
  end

  after do
    @post.destroy
    @comment1.destroy
    @comment2.destroy
    @like1.destroy
    @like2.destroy
  end

  describe '#root' do
    it 'contains the first node of the graph' do
      assert query.root.is_a?(GraphQL::Syntax::Node)
    end
  end

  describe '#as_json' do

    it 'performs the root node call' do
      assert_send([Nodes::PostNode, :call, "123"])
      query.as_json
    end

    it 'finds fields that delegate to a target' do
      assert_equal query.as_json, {
        "123" => {
          "title" => "My great post",
          "content" => "So many great things"
        }
      }
    end

    describe 'when requesting fields defined on the node' do
      let(:query_string) { "post(123) { teaser } "}
      it 'finds fields defined on the node' do
        assert_equal query.as_json, { "123" => { "teaser" => @post.content[0,10] + "..."}}
      end
    end


    describe 'when requesting an undefined field' do
      let(:query_string) { "post(123) { destroy } "}
      it 'raises a FieldNotDefined error' do
        assert_raises(GraphQL::FieldNotDefinedError) { query.as_json }
        assert(Post.find(123).present?)
      end
    end

    describe 'when the root call doesnt have an argument' do
      let(:query_string) { "viewer() { name }"}
      it 'calls the node with no arguments' do
        assert_send([Nodes::ViewerNode, :call])
        query.as_json
      end
    end

    describe  'when requesting a collection' do
      let(:query_string) { "post(123) {
          title,
          comments { count, edges { cursor, node { content } } }
        }"}
      it 'returns collection data' do
        assert_equal query.as_json, {
            "123" => {
              "title" => "My great post",
              "comments" => {
                "count" => 2,
                "edges" => [
                  { "cursor" => "444", "node" => {"content" => "I agree"} },
                  { "cursor" => "445", "node" => {"content" => "I disagree"}}
                ]
            }}}
      end
    end

    describe  'when making calls on a collection' do
      let(:query_string) { "post(123) { comments.first(1) { edges { cursor, node { content } } } }"}

      it 'executes those calls' do
        assert_equal query.as_json, {
            "123" => {
              "comments" => {
                "edges" => [
                  { "cursor" => "444", "node" => { "content" => "I agree"} }
                ]
            }}}
      end
    end

    describe  'when making DEEP calls on a collection' do
      let(:query_string) { "post(123) { comments.after(444).first(1) {
            edges { cursor, node { content } }
          }}"}

      it 'executes those calls' do
        assert_equal query.as_json, {
            "123" => {
              "comments" => {
                "edges" => [
                  {
                    "cursor" => "445",
                    "node" => { "content" => "I disagree"}
                  }
                ]
            }}}
      end
    end

    describe  'when requesting fields at collection-level' do
      let(:query_string) { "post(123) { comments { average_rating } }"}

      it 'executes those calls' do
        assert_equal query.as_json, { "123" => { "comments" => { "average_rating" => 3 } } }
      end
    end

    describe  'when requesting collection-level fields that dont exist' do
      let(:query_string) { "post(123) { comments { bogus_field } }"}

      it 'raises FieldNotDefined' do
        assert_raises(GraphQL::FieldNotDefinedError) { query.as_json }
      end
    end
  end

  describe '.default_namespace=' do
    let(:query) { GraphQL::Query.new(query_string) }
    after { GraphQL::Query.default_namespace = nil }

    it 'uses that namespace for lookups' do
      GraphQL::Query.default_namespace = Nodes
      assert_equal query.as_json, {
        "123" => {
          "title" => "My great post",
          "content" => "So many great things"
        }
      }
    end
  end

  describe 'when edge nodes were named explicitly' do
    let(:query_string) { "post(123) { likes { any, edges { node { id } } } }"}
    let(:result) { query.as_json }

    it 'gets node values' do
      assert_equal [991,992], result["123"]["likes"]["edges"].map {|e|  e["node"]["id"] }
    end

    it 'gets edge values' do
      assert_equal true, result["123"]["likes"]["any"]
    end
  end
end